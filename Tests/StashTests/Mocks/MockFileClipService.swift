// MockFileClipService — FileClipService protocol 테스트용 in-memory 구현체
@testable import stash
import Foundation

final class MockFileClipService: FileClipService, @unchecked Sendable {
    var savedFiles: [(URL, ClipType)] = []
    var deletedClips: [Clip] = []
    var shouldThrow = false
    /// TASK-026 — saveFiles 호출 시 throwAtIndex 박혀있으면 해당 index 에서 throw (부분 실패 시뮬레이션).
    var throwAtIndex: Int? = nil
    /// TASK-026 — saveFiles 입력 기록.
    var savedFilesBatch: [[URL]] = []
    /// TASK-034 — sweepOrphans 호출 시 referencedPaths 인자 기록.
    var sweepCalls: [Set<String>] = []

    func saveData(_ data: Data, type: ClipType) async throws -> StoredFile {
        if shouldThrow { throw ClipboardError.pasteboardUnavailable }
        let url = URL(fileURLWithPath: "/mock/\(UUID().uuidString).\(type == .image ? "png" : "bin")")
        savedFiles.append((url, type))
        return StoredFile(filePath: url, isFileExternal: false)
    }

    func saveFile(at sourceURL: URL) async throws -> StoredFile {
        if shouldThrow { throw ClipboardError.pasteboardUnavailable }
        savedFiles.append((sourceURL, .file))
        return StoredFile(filePath: sourceURL, isFileExternal: false)
    }

    /// TASK-026 — 다중 카피 mock. throwAtIndex 박혀있으면 해당 index 에서 throw.
    func saveFiles(at sources: [URL]) async throws -> [StoredFile] {
        savedFilesBatch.append(sources)
        if shouldThrow { throw ClipboardError.pasteboardUnavailable }
        var stored: [StoredFile] = []
        for (idx, url) in sources.enumerated() {
            if let failIdx = throwAtIndex, failIdx == idx {
                throw ClipboardError.pasteboardUnavailable
            }
            stored.append(StoredFile(filePath: url, isFileExternal: false))
        }
        return stored
    }

    func delete(_ clip: Clip) async throws {
        if shouldThrow { throw ClipboardError.pasteboardUnavailable }
        deletedClips.append(clip)
    }

    /// TASK-034 — sweepOrphans 호출 시 인자 기록 (실제 파일 삭제 X — 테스트는 호출 인자만 검증).
    func sweepOrphans(referencedPaths: Set<String>) async {
        sweepCalls.append(referencedPaths)
    }
}
