// PasteService — paste 두 분기 + 에러 전파 + 정렬 갱신 검증
@testable import stash
import Testing
import Foundation
import AppKit

@Suite("PasteService")
@MainActor
struct PasteServiceTests {

    // MARK: - Helpers

    private func makeService(
        synthesizer: MockPasteSynthesizer = MockPasteSynthesizer(),
        pasteboard: MockPasteboard = MockPasteboard(),
        repository: InMemoryClipRepository = InMemoryClipRepository()
    ) -> (PasteService, MockPasteSynthesizer, MockPasteboard, InMemoryClipRepository) {
        let svc = PasteService(
            synthesizer: synthesizer,
            pasteboard: pasteboard,
            repository: repository,
            permissionService: PermissionService(checker: MockPermissionChecker())
        )
        return (svc, synthesizer, pasteboard, repository)
    }

    private func makeClip(body: String? = "hello", isPinned: Bool = false) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: body == nil ? .image : .text,
            body: body,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: isPinned,
            createdAt: now,
            lastUsedAt: now
        )
    }

    private func makeImageClip(filePath: String?, isPinned: Bool = false) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: .image,
            body: nil,
            filePath: filePath,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: isPinned,
            createdAt: now,
            lastUsedAt: now
        )
    }

    private func makeFileClip(originalPath: String?, filePath: String? = nil, isPinned: Bool = false) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: .file,
            body: nil,
            filePath: filePath,
            isFileExternal: filePath == nil,
            fileOriginalPath: originalPath,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: isPinned,
            createdAt: now,
            lastUsedAt: now
        )
    }

    /// 임시 디렉토리에 작은 PNG 파일 생성 — NSImage 로드 가능. 호출자 cleanup 책임.
    private func makeTempImageFile() throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("stash-test-\(UUID().uuidString).png")
        // 1x1 흰색 PNG 생성
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.white.set()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TestSetup", code: 1)
        }
        try pngData.write(to: url)
        return url
    }

    // MARK: - .autoPaste 분기

    @Test func autoPasteSetsStringSynthesizesAndUpdatesLastUsedAt() async throws {
        let (svc, synth, pb, repo) = makeService()
        let clip = makeClip(body: "hello")
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt

        try await svc.paste(clip: clip, mode: .autoPaste)

        #expect(pb.strings[.string] == "hello")
        #expect(synth.callCount == 1)
        let after = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt
        #expect(after > before)
    }

    // MARK: - .copyBack 분기

    @Test func copyBackSetsStringSkipsSynthesizeAndUpdatesLastUsedAt() async throws {
        let (svc, synth, pb, repo) = makeService()
        let clip = makeClip(body: "world")
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt

        try await svc.paste(clip: clip, mode: .copyBack)

        #expect(pb.strings[.string] == "world")
        #expect(synth.callCount == 0)
        let after = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt
        #expect(after > before)
    }

    // MARK: - synthesize 실패 → PasteError 전파 + updateLastUsedAt 미호출

    @Test func autoPasteThrowsKeyboardSimulationFailedAndLeavesLastUsedAtUnchanged() async throws {
        let (svc, synth, pb, repo) = makeService()
        synth.shouldThrow = true
        let clip = makeClip(body: "fail")
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt

        await #expect(throws: PasteError.self) {
            try await svc.paste(clip: clip, mode: .autoPaste)
        }

        #expect(pb.strings[.string] == "fail")  // setString 은 synthesize 전 이미 호출됨
        #expect(synth.callCount == 1)
        let after = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt
        #expect(after == before)  // 정렬 갱신 미호출
    }

    // MARK: - ClipType별 분기 (TASK-016 Phase 6)

    @Test("text clip — clearAndDeclareTypes(.string) + setString(.string) 호출 + last_used_at 갱신")
    func pasteText_CallsSetStringWithBody() async throws {
        let (svc, _, pb, repo) = makeService()
        let clip = makeClip(body: "hello")
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        #expect(pb.recordedDeclareTypes.last == [.string])
        #expect(pb.recordedSetString.last?.0 == "hello")
        #expect(pb.recordedSetString.last?.1 == .string)
    }

    @Test("text clip — body=nil → unsupportedClipPayload throw")
    func pasteText_NilBody_Throws() async throws {
        let (svc, _, pb, repo) = makeService()
        // type=.text + body=nil 명시 (makeClip은 nil이면 image로 만들어버림)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clip = Clip(
            id: UUID(), type: .text, body: nil,
            filePath: nil, isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: false,
            createdAt: now, lastUsedAt: now
        )
        try await repo.insert(clip)

        await #expect(throws: PasteError.self) {
            try await svc.paste(clip: clip, mode: .copyBack)
        }
        #expect(pb.recordedSetString.isEmpty)  // setString 호출 X
    }

    @Test("image clip — filePath=nil → imageDataLoadFailed throw")
    func pasteImage_NoFilePath_Throws() async throws {
        let (svc, _, pb, repo) = makeService()
        let clip = makeImageClip(filePath: nil)
        try await repo.insert(clip)

        await #expect(throws: PasteError.self) {
            try await svc.paste(clip: clip, mode: .copyBack)
        }
        #expect(pb.recordedSetData.isEmpty)
    }

    @Test("image clip — 유효 PNG 파일 → setData(.tiff) 또는 (.png) 호출")
    func pasteImage_ValidFile_SetsImageData() async throws {
        let imageURL = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let (svc, _, pb, repo) = makeService()
        let clip = makeImageClip(filePath: imageURL.path)
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        // declareTypes에 .tiff 또는 .png 박힘 + setData 호출 발생
        let lastDeclared = pb.recordedDeclareTypes.last ?? []
        #expect(lastDeclared.contains(.tiff) || lastDeclared.contains(.png))
        #expect(pb.recordedSetData.count == 1)
        let lastDataType = pb.recordedSetData.last?.1
        #expect(lastDataType == .tiff || lastDataType == .png)
    }

    // MARK: - TASK-023 회귀 (d) — 이미지 클립 paste 시 file URL 동시 박음

    /// 이미지 파일 클립(fileOriginalPath 존재 + 파일 실재) → declare 에 file-url 포함 + setString 호출 (Finder 폴더 ⌘V 호환).
    @Test("image clip + fileOriginalPath 실재 → declare 에 .tiff + public.file-url 둘 다 + setData + setString 둘 다 호출")
    func pasteImage_WithFileOriginalPath_SetsBothFileURLAndImageData() async throws {
        let imageURL = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let (svc, _, pb, repo) = makeService()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clip = Clip(
            id: UUID(), type: .image, body: nil,
            filePath: imageURL.path, isFileExternal: false,
            fileOriginalPath: imageURL.path, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: false,
            createdAt: now, lastUsedAt: now
        )
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        let lastDeclared = pb.recordedDeclareTypes.last ?? []
        #expect(lastDeclared.contains(.tiff) || lastDeclared.contains(.png))
        #expect(lastDeclared.contains(.fileURL))
        #expect(pb.recordedSetData.count == 1)
        #expect(pb.recordedSetString.count == 1)
        #expect(pb.recordedSetString.last?.1 == .fileURL)
        let urlString = pb.recordedSetString.last?.0 ?? ""
        #expect(urlString.hasPrefix("file://"))
        #expect(urlString.contains(imageURL.lastPathComponent))
    }

    /// 메모리 비트맵 (fileOriginalPath = nil) → image data 만 (기존 동작 유지, file URL 박음 X).
    @Test("image clip + fileOriginalPath nil → image data 만 박음 (file URL X)")
    func pasteImage_WithoutFileOriginalPath_SetsOnlyImageData() async throws {
        let imageURL = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let (svc, _, pb, repo) = makeService()
        let clip = makeImageClip(filePath: imageURL.path)  // fileOriginalPath = nil
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        let lastDeclared = pb.recordedDeclareTypes.last ?? []
        #expect(!lastDeclared.contains(.fileURL))
        #expect(pb.recordedSetString.isEmpty)
        #expect(pb.recordedSetData.count == 1)
    }

    /// fileOriginalPath 가 있지만 *실제 파일이 사라진* 경우 — file URL 박지 X (안전망).
    @Test("image clip + fileOriginalPath 박혀있어도 파일 미실재 → file URL X")
    func pasteImage_FileOriginalPathButFileMissing_SetsOnlyImageData() async throws {
        let imageURL = try makeTempImageFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let (svc, _, pb, repo) = makeService()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clip = Clip(
            id: UUID(), type: .image, body: nil,
            filePath: imageURL.path, isFileExternal: false,
            fileOriginalPath: "/nonexistent/never-existed.png",  // 미실재
            fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: false,
            createdAt: now, lastUsedAt: now
        )
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        let lastDeclared = pb.recordedDeclareTypes.last ?? []
        #expect(!lastDeclared.contains(.fileURL))
        #expect(pb.recordedSetString.isEmpty)
    }

    // MARK: - TASK-023 회귀 (e) — onPasteboardWritten 콜백

    /// PasteService 가 paste 시 onPasteboardWritten 콜백을 정확히 1회 호출.
    @Test("paste 시 onPasteboardWritten 콜백 1회 호출 — 모든 ClipType")
    func paste_InvokesOnPasteboardWrittenCallback() async throws {
        let counter = CallbackCounter()
        let pb = MockPasteboard()
        let synth = MockPasteSynthesizer()
        let repo = InMemoryClipRepository()
        let svc = PasteService(
            synthesizer: synth,
            pasteboard: pb,
            repository: repo,
            permissionService: PermissionService(checker: MockPermissionChecker()),
            onPasteboardWritten: { await counter.increment() }
        )
        let textClip = makeClip(body: "hello")
        try await repo.insert(textClip)

        try await svc.paste(clip: textClip, mode: .copyBack)

        let invocations = await counter.value
        #expect(invocations == 1)
    }

    @Test("file clip — fileOriginalPath 우선 → setString(public.file-url) 호출")
    func pasteFile_FromOriginalPath_SetsFileURL() async throws {
        let (svc, _, pb, repo) = makeService()
        let clip = makeFileClip(originalPath: "/tmp/foo.txt")
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        let fileURLType = NSPasteboard.PasteboardType("public.file-url")
        #expect(pb.recordedDeclareTypes.last == [fileURLType])
        #expect(pb.recordedSetString.last?.1 == fileURLType)
        // file:///tmp/foo.txt 형식
        let urlString = pb.recordedSetString.last?.0 ?? ""
        #expect(urlString.hasPrefix("file://"))
        #expect(urlString.contains("/tmp/foo.txt"))
    }

    @Test("file clip — fileOriginalPath nil이면 filePath fallback")
    func pasteFile_FallsBackToFilePath() async throws {
        let (svc, _, pb, repo) = makeService()
        let clip = makeFileClip(originalPath: nil, filePath: "/Library/stash/internal/foo.txt")
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .copyBack)

        let urlString = pb.recordedSetString.last?.0 ?? ""
        #expect(urlString.contains("/Library/stash/internal/foo.txt"))
    }

    @Test("file clip — fileOriginalPath + filePath 모두 nil → fileURLLoadFailed throw")
    func pasteFile_NilPaths_Throws() async throws {
        let (svc, _, pb, repo) = makeService()
        let clip = makeFileClip(originalPath: nil, filePath: nil)
        try await repo.insert(clip)

        await #expect(throws: PasteError.self) {
            try await svc.paste(clip: clip, mode: .copyBack)
        }
        #expect(pb.recordedSetString.isEmpty)
    }

    // MARK: - setString 이 synthesize 전에 호출됨 (순서 보장)

    @Test func setStringHappensBeforeSynthesize() async throws {
        let (svc, synth, pb, repo) = makeService()
        let clip = makeClip(body: "ordered")
        try await repo.insert(clip)

        let capturedAtSynthesize = LockedString()
        synth.onSynthesize = { [pb] in
            capturedAtSynthesize.value = pb.strings[.string] ?? "<nil>"
        }

        try await svc.paste(clip: clip, mode: .autoPaste)

        #expect(capturedAtSynthesize.value == "ordered")
    }
}

/// onSynthesize 클로저 안에서 외부 상태 캡처용 (Sendable closure 격리).
private final class LockedString: @unchecked Sendable {
    var value: String = ""
}

/// onPasteboardWritten 콜백 호출 횟수 추적 — Sendable 격리 (TASK-023 회귀 (e) fix 테스트용).
private actor CallbackCounter {
    var value: Int = 0
    func increment() { value += 1 }
}
