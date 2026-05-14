// DirectFileClipService — saveData / saveFile / delete 세 메서드 전 분기 검증
@testable import stash
import Testing
import Foundation

@Suite("DirectFileClipService")
@MainActor
struct DirectFileClipServiceTests {

    // MARK: - Helpers

    private func makeTempFolder() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
    }

    private func makeService(
        tempFolder: URL,
        maxFileSize: Int = Int.max
    ) -> DirectFileClipService {
        DirectFileClipService(clipsFolder: tempFolder, maxFileSize: maxFileSize)
    }

    private func makeClip(filePath: String?, isFileExternal: Bool) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: .file,
            body: nil,
            filePath: filePath,
            isFileExternal: isFileExternal,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: now,
            lastUsedAt: now
        )
    }

    private func makeTempFile(in folder: URL, name: String, content: Data = Data("hello".utf8)) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - saveData

    @Test func saveDataImageCreatesPngFile() async throws {
        let tempFolder = makeTempFolder()
        defer { cleanup(tempFolder) }
        let svc = makeService(tempFolder: tempFolder)

        let stored = try await svc.saveData(Data("fake-png".utf8), type: .image)

        #expect(stored.filePath.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: stored.filePath.path))
    }

    @Test func saveDataBinaryCreatesBinFile() async throws {
        let tempFolder = makeTempFolder()
        defer { cleanup(tempFolder) }
        let svc = makeService(tempFolder: tempFolder)

        let stored = try await svc.saveData(Data("raw-data".utf8), type: .file)

        #expect(stored.filePath.pathExtension == "bin")
        #expect(FileManager.default.fileExists(atPath: stored.filePath.path))
    }

    @Test func saveDataCreatesFolderIfMissing() async throws {
        let tempFolder = makeTempFolder()  // 존재하지 않는 경로
        defer { cleanup(tempFolder) }
        let svc = makeService(tempFolder: tempFolder)

        let stored = try await svc.saveData(Data("x".utf8), type: .image)

        #expect(FileManager.default.fileExists(atPath: stored.filePath.path))
    }

    @Test func saveDataReturnsIsFileExternalFalse() async throws {
        let tempFolder = makeTempFolder()
        defer { cleanup(tempFolder) }
        let svc = makeService(tempFolder: tempFolder)

        let stored = try await svc.saveData(Data("x".utf8), type: .image)

        #expect(stored.isFileExternal == false)
    }

    // MARK: - saveFile

    @Test func saveFileUnderLimitCopiesFile() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }
        let sourceURL = try makeTempFile(in: sourceFolder, name: "document.pdf")
        let svc = makeService(tempFolder: clipsFolder)

        let stored = try await svc.saveFile(at: sourceURL)

        #expect(stored.isFileExternal == false)
        #expect(FileManager.default.fileExists(atPath: stored.filePath.path))
        #expect(stored.filePath.path != sourceURL.path)
    }

    @Test func saveFileOverLimitReturnsExternalRef() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }
        let sourceURL = try makeTempFile(in: sourceFolder, name: "huge.zip")
        // maxFileSize=0 → 어떤 파일도 임계값 초과
        let svc = makeService(tempFolder: clipsFolder, maxFileSize: 0)

        let stored = try await svc.saveFile(at: sourceURL)

        #expect(stored.isFileExternal == true)
        #expect(stored.filePath == sourceURL)
    }

    @Test func saveFileCopyEmbedOriginalName() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }
        let sourceURL = try makeTempFile(in: sourceFolder, name: "myfile.txt")
        let svc = makeService(tempFolder: clipsFolder)

        let stored = try await svc.saveFile(at: sourceURL)

        #expect(stored.filePath.lastPathComponent.contains("myfile.txt"))
    }

    // MARK: - delete

    @Test func deleteNonExternalFileRemovesFromDisk() async throws {
        let clipsFolder = makeTempFolder()
        defer { cleanup(clipsFolder) }
        let svc = makeService(tempFolder: clipsFolder)
        let stored = try await svc.saveData(Data("to-delete".utf8), type: .image)
        let clip = makeClip(filePath: stored.filePath.path, isFileExternal: false)

        try await svc.delete(clip)

        #expect(!FileManager.default.fileExists(atPath: stored.filePath.path))
    }

    @Test func deleteExternalClipIsNoOp() async throws {
        let sourceFolder = makeTempFolder()
        defer { cleanup(sourceFolder) }
        let sourceURL = try makeTempFile(in: sourceFolder, name: "external.txt")
        let clip = makeClip(filePath: sourceURL.path, isFileExternal: true)
        let svc = makeService(tempFolder: makeTempFolder())

        try await svc.delete(clip)

        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }
}
