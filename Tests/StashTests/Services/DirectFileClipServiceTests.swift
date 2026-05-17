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

    // MARK: - TASK-026 — saveFiles + delete 다중 분기

    /// 3 URL 전체 성공 — 모두 ≤maxFileSize → 카피본 생성 + isFileExternal=false.
    @Test func saveFilesAllSucceed() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }

        let url1 = try makeTempFile(in: sourceFolder, name: "a.txt")
        let url2 = try makeTempFile(in: sourceFolder, name: "b.png")
        let url3 = try makeTempFile(in: sourceFolder, name: "c.pdf")
        let svc = makeService(tempFolder: clipsFolder)

        let stored = try await svc.saveFiles(at: [url1, url2, url3])

        #expect(stored.count == 3)
        for sf in stored {
            #expect(sf.isFileExternal == false)
            #expect(FileManager.default.fileExists(atPath: sf.filePath.path))
        }
    }

    /// entry 사이즈 분기 — >maxFileSize 시 isFileExternal=true (원본 경로 그대로).
    @Test func saveFilesEntrySizeBranching() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }

        // 1바이트 임계로 — 빈 파일(0 bytes)은 카피, 1바이트 이상은 external.
        let small = try makeTempFile(in: sourceFolder, name: "small.txt", content: Data())  // 0 bytes
        let large = try makeTempFile(in: sourceFolder, name: "large.bin", content: Data(repeating: 0xFF, count: 2))
        let svc = makeService(tempFolder: clipsFolder, maxFileSize: 1)

        let stored = try await svc.saveFiles(at: [small, large])

        #expect(stored.count == 2)
        #expect(stored[0].isFileExternal == false)
        #expect(stored[1].isFileExternal == true)
        #expect(stored[1].filePath == large)  // 원본 경로 그대로
    }

    /// 중간 실패 — 2번째 URL 존재 X → throw + 1번째 카피본 cleanup.
    @Test func saveFilesPartialFailureCleansUpCarbonCopies() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }

        let url1 = try makeTempFile(in: sourceFolder, name: "exists.txt")
        let url2 = URL(fileURLWithPath: "/tmp/__nonexistent_\(UUID().uuidString).txt")
        let svc = makeService(tempFolder: clipsFolder)

        var thrown = false
        do {
            _ = try await svc.saveFiles(at: [url1, url2])
        } catch {
            thrown = true
        }
        #expect(thrown)

        // 1번째 카피본 cleanup 검증 — clips 폴더 안 아무 파일도 없어야 함.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: clipsFolder.path)) ?? []
        #expect(contents.isEmpty)
    }

    /// 다중 파일 Clip 삭제 — entries 순회 cleanup. isFileExternal=true entry 는 원본 보호.
    @Test func deleteMultiFileClipCleansUpInternalOnly() async throws {
        let sourceFolder = makeTempFolder()
        let clipsFolder = makeTempFolder()
        defer { cleanup(sourceFolder); cleanup(clipsFolder) }

        // 내부 카피본 1개 (clipsFolder 안) + 외부 원본 1개 (sourceFolder 안)
        let internalURL = clipsFolder.appendingPathComponent("\(UUID().uuidString)_a.txt")
        try FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: internalURL)
        let externalURL = try makeTempFile(in: sourceFolder, name: "external.bin")

        let entries = [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: internalURL.path, isFileExternal: false),
            ClipFileEntry(originalPath: externalURL.path, filePath: externalURL.path, isFileExternal: true)
        ]
        let json = try ClipFileEntry.encodeJSON(entries)

        var clip = makeClip(filePath: nil, isFileExternal: false)
        clip.filePathsJson = json
        let svc = makeService(tempFolder: clipsFolder)

        try await svc.delete(clip)

        #expect(!FileManager.default.fileExists(atPath: internalURL.path))  // 내부 카피본 삭제
        #expect(FileManager.default.fileExists(atPath: externalURL.path))   // 외부 원본 보호
    }

    /// 다중 파일 Clip 의 잘못된 JSON — silent return (main 흐름 영향 0).
    @Test func deleteMultiFileClipMalformedJsonReturnsSilently() async throws {
        let clipsFolder = makeTempFolder()
        defer { cleanup(clipsFolder) }
        var clip = makeClip(filePath: nil, isFileExternal: false)
        clip.filePathsJson = "not-a-json"
        let svc = makeService(tempFolder: clipsFolder)

        // throws X — silent return
        try await svc.delete(clip)
        #expect(true)
    }
}
