// FileClipService protocol의 v1.0 구현체 — 파일 클립을 로컬 clips/ 폴더에 복사
import Foundation
import OSLog

actor DirectFileClipService: FileClipService {
    private let clipsFolder: URL
    private let maxFileSize: Int

    init(clipsFolder: URL = AppDataPath.clipsFolder(), maxFileSize: Int = Constants.fileClipCopyMaxSize) {
        self.clipsFolder = clipsFolder
        self.maxFileSize = maxFileSize
    }

    func saveData(_ data: Data, type: ClipType) async throws -> StoredFile {
        let ext = type == .image ? "png" : "bin"
        let dest = clipsFolder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)
        try data.write(to: dest)
        return StoredFile(filePath: dest, isFileExternal: false)
    }

    func saveFile(at sourceURL: URL) async throws -> StoredFile {
        let attrs = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = attrs[.size] as? Int ?? 0
        if size > maxFileSize {
            return StoredFile(filePath: sourceURL, isFileExternal: true)
        }
        let dest = clipsFolder.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
        try FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return StoredFile(filePath: dest, isFileExternal: false)
    }

    /// TASK-026 — 다중 파일 카피. 옵션 A 정합 — 어느 하나라도 실패 시 *이미 카피된 N-K개 cleanup* 후 throw.
    /// 순차 카피 (병렬 X — 디스크 IO 직렬화 + 에러 진단 단순).
    func saveFiles(at sources: [URL]) async throws -> [StoredFile] {
        var stored: [StoredFile] = []
        stored.reserveCapacity(sources.count)
        do {
            for url in sources {
                let result = try await saveFile(at: url)
                stored.append(result)
            }
            Logger.clipboard.info("saveFiles: \(sources.count) succeeded")
            return stored
        } catch {
            // 옵션 A — 이미 카피된 stash 카피본 cleanup (external entry 원본은 보호).
            let copied = stored.count
            Logger.clipboard.error("saveFiles: failed at entry \(copied) — rollback \(copied) carbon copies, error=\(error)")
            for sf in stored where !sf.isFileExternal {
                try? FileManager.default.removeItem(at: sf.filePath)
            }
            throw error
        }
    }

    func delete(_ clip: Clip) async throws {
        // TASK-026 — 다중 파일 묶음이면 별도 helper 위임 (delete SRP).
        if clip.isMultiFile {
            deleteMultiFileEntries(clip)
            return
        }
        guard !clip.isFileExternal, let pathStr = clip.filePath else { return }
        let url = URL(fileURLWithPath: pathStr)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// TASK-026 — 다중 파일 묶음 entries 순회 cleanup. entry별 `isFileExternal=false` 만 디스크 삭제 (외부 원본 보호).
    /// decode 실패 / 파일 미존재는 silent skip — main 흐름 영향 0.
    private func deleteMultiFileEntries(_ clip: Clip) {
        guard let entries = clip.fileEntries else {
            Logger.database.info("delete multi-file: fileEntries decode 실패 — cleanup skip (clipId=\(clip.id))")
            return
        }
        Logger.database.info("delete multi-file: \(entries.count) entries")
        for entry in entries where !entry.isFileExternal {
            let url = URL(fileURLWithPath: entry.filePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// TASK-034 — clips/ 폴더 enumerate → referencedPaths 미포함 파일 삭제.
    /// 폴더 미존재 / removeItem 실패 silent + 로깅 (orphan sweep 자체 실패가 main 흐름 차단 X).
    /// symlink 정규화 (`resolvingSymlinksInPath`) 필수 — macOS 의 `/var → /private/var` 차이로 인한 false-orphan 분류 회피.
    func sweepOrphans(referencedPaths: Set<String>) async {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: clipsFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            Logger.database.debug("sweepOrphans: clipsFolder enumerate skip — \(error.localizedDescription)")
            return
        }
        let normalizedReferenced = Set(referencedPaths.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        })
        var removed = 0
        for url in contents {
            let normalizedPath = url.resolvingSymlinksInPath().path
            if normalizedReferenced.contains(normalizedPath) { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                Logger.database.error("sweepOrphans: removeItem failed — \(url.lastPathComponent) error=\(error.localizedDescription)")
            }
        }
        Logger.database.info("sweepOrphans: removed \(removed) orphan file(s) (referenced=\(referencedPaths.count), scanned=\(contents.count))")
    }
}
