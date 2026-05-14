// MockFileClipService — FileClipService protocol 테스트용 in-memory 구현체
@testable import stash
import Foundation

final class MockFileClipService: FileClipService, @unchecked Sendable {
    var savedFiles: [(URL, ClipType)] = []
    var deletedClips: [Clip] = []
    var shouldThrow = false

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

    func delete(_ clip: Clip) async throws {
        if shouldThrow { throw ClipboardError.pasteboardUnavailable }
        deletedClips.append(clip)
    }
}
