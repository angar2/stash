// FileClipService protocol의 v1.0 구현체 — 파일 클립을 로컬 clips/ 폴더에 복사
import Foundation

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

    func delete(_ clip: Clip) async throws {
        guard !clip.isFileExternal, let pathStr = clip.filePath else { return }
        let url = URL(fileURLWithPath: pathStr)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
