// ClipboardWatcher actor 단위 테스트 — tick() / buildClip 분기 / LRU 파일 삭제 연동
@testable import stash
import Testing
import Foundation
import AppKit

@Suite("ClipboardWatcher")
struct ClipboardWatcherTests {

    // MARK: - Helpers

    private func makeWatcher(
        pasteboard: MockPasteboard = MockPasteboard(),
        fileClipService: MockFileClipService = MockFileClipService(),
        repository: InMemoryClipRepository = InMemoryClipRepository()
    ) -> ClipboardWatcher {
        ClipboardWatcher(
            pasteboard: pasteboard,
            fileClipService: fileClipService,
            repository: repository
        )
    }

    // MARK: - changeCount 동일 — idle

    @Test func tickIdleWhenChangeCountUnchanged() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 0
        pb.setString("hello", forType: .string)
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        // 첫 tick — lastChangeCount 초기값 -1이므로 변경 감지 → insert 1회
        await watcher.tick()
        let countAfterFirst = try await repo.fetchAll().count
        #expect(countAfterFirst == 1)

        // 두 번째 tick — changeCount 동일 → idle (insert 없음)
        await watcher.tick()
        let countAfterSecond = try await repo.fetchAll().count
        #expect(countAfterSecond == 1)
    }

    // MARK: - TransientType 감지 — insert 0회

    @Test func tickSkipsTransientType() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.availableTypes = [NSPasteboard.PasteboardType("org.nspasteboard.TransientType")]
        pb.setString("secret", forType: .string)
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.isEmpty)
    }

    // MARK: - 텍스트 클립

    @Test func tickInsertsTextClip() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.setString("hello world", forType: .string)
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .text)
        #expect(clips[0].body == "hello world")
    }

    // MARK: - 이미지 클립 — 메모리 비트맵 (B 케이스, file URL 없음)

    @Test func tickInsertsImageClip() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.availableTypes = [.tiff]
        pb.dataStore[.tiff] = Data("fake-img".utf8)
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .image)
        #expect(clips[0].fileOriginalPath == nil)
        #expect(fileSvc.savedFiles.count == 1)
    }

    // MARK: - 파일 URL 클립 — 확장자 비이미지 (.file)

    @Test func tickInsertsFileClip() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.strings[NSPasteboard.PasteboardType("public.file-url")] = "file:///tmp/test.pdf"
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .file)
        #expect(fileSvc.savedFiles.count == 1)
    }

    // MARK: - TASK-023 분류 우선순위 회귀 차단

    /// (c) txt 파일 + Quick Look 썸네일(.tiff) 동시 박힘 → .file 클립 (이미지 오분류 X).
    @Test func tickReclassifiesTxtFileWithImagePreviewAsFile() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.strings[.fileURL] = "file:///tmp/test.txt"
        pb.availableTypes = [.fileURL, .tiff]
        pb.dataStore[.tiff] = Data("preview".utf8)
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .file)
        #expect(clips[0].fileOriginalPath == "/tmp/test.txt")
        // saveFile 호출 검증 — saveFile은 원본 URL 그대로 push, saveData는 /mock/<uuid>.png push.
        #expect(fileSvc.savedFiles.count == 1)
        #expect(fileSvc.savedFiles[0].0 == URL(fileURLWithPath: "/tmp/test.txt"))
    }

    /// 이미지 파일 file URL + 썸네일 데이터 → .image 클립 + fileOriginalPath 박힘 (C 케이스).
    @Test func tickClassifiesImageFileURLAsImageClip() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.strings[.fileURL] = "file:///tmp/photo.png"
        pb.availableTypes = [.fileURL, .tiff]
        pb.dataStore[.tiff] = Data("img".utf8)
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .image)
        #expect(clips[0].fileOriginalPath == "/tmp/photo.png")
        // saveFile 호출 검증 — file URL 분기.
        #expect(fileSvc.savedFiles.count == 1)
        #expect(fileSvc.savedFiles[0].0 == URL(fileURLWithPath: "/tmp/photo.png"))
    }

    /// 메모리 비트맵 (file URL 없음) → .image 클립 + fileOriginalPath nil (B 케이스). 기존 동작 회귀 확인.
    @Test func tickClassifiesPasteboardImageDataAsImageClipWithoutOriginalPath() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.availableTypes = [.tiff]
        pb.dataStore[.tiff] = Data("img".utf8)
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .image)
        #expect(clips[0].fileOriginalPath == nil)
        // saveData 호출 검증 — MockFileClipService.saveData는 /mock/<uuid>.png 형태 URL push.
        #expect(fileSvc.savedFiles.count == 1)
        #expect(fileSvc.savedFiles[0].0.path.hasPrefix("/mock/"))
        #expect(fileSvc.savedFiles[0].0.pathExtension == "png")
    }

    /// 대소문자 무관 확장자 매칭 — `.PNG` 도 `.image` 분기.
    @Test func tickHandlesUppercaseImageExtension() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.strings[.fileURL] = "file:///tmp/PHOTO.PNG"
        pb.availableTypes = [.fileURL]
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .image)
        #expect(clips[0].fileOriginalPath == "/tmp/PHOTO.PNG")
    }

    // MARK: - TASK-023 회귀 (e) — self-write skip

    /// `acknowledgeOwnWrite()` 호출 후 동일 changeCount 의 다음 tick 은 idle (repository.insert 0회).
    /// PasteService 가 박은 pasteboard 변경을 watcher 가 새 클립으로 재감지하던 회귀 차단.
    @Test func acknowledgeOwnWrite_SkipsNextTick() async throws {
        let pb = MockPasteboard()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        // 1. 첫 변경 — 외부에서 박음 (예: 다른 앱 ⌘C).
        pb.changeCount = 5
        pb.setString("first", forType: .string)
        await watcher.tick()
        #expect(try await repo.fetchAll().count == 1)

        // 2. PasteService 가 박음 — pasteboard.changeCount 증가 시뮬레이션.
        pb.availableTypes = [.tiff]
        pb.dataStore[.tiff] = Data("paste-out".utf8)
        pb.changeCount = 7

        // 3. PasteService 가 acknowledgeOwnWrite() 호출 — lastChangeCount 동기화.
        await watcher.acknowledgeOwnWrite()

        // 4. 다음 tick — idle (insert 0회 추가).
        await watcher.tick()
        #expect(try await repo.fetchAll().count == 1)  // 여전히 1
    }

    // MARK: - TASK-023 회귀 (g) — 웹 이미지 source URL

    /// 웹페이지 우클릭 이미지 복사 시 `public.url` 박힘 → `clip.body` 에 URL 박힘.
    @Test func tickRecordsWebURLAsBodyForMemoryBitmapImage() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.availableTypes = [.tiff]
        pb.dataStore[.tiff] = Data("web-img".utf8)
        pb.strings[.URL] = "https://example.com/photos/logo.png"
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .image)
        #expect(clips[0].body == "https://example.com/photos/logo.png")
        #expect(clips[0].fileOriginalPath == nil)  // 메모리 비트맵 — 원본 file path X
    }

    /// 스크린샷 (`public.url` 없음) → `clip.body` 그대로 nil (기존 동작 유지).
    @Test func tickLeavesBodyNilForScreenshotImage() async throws {
        let pb = MockPasteboard()
        pb.changeCount = 1
        pb.availableTypes = [.tiff]
        pb.dataStore[.tiff] = Data("screenshot".utf8)
        // public.url 미박음
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        await watcher.tick()
        let clips = try await repo.fetchAll()
        #expect(clips.count == 1)
        #expect(clips[0].type == .image)
        #expect(clips[0].body == nil)
        #expect(clips[0].fileOriginalPath == nil)
    }

    /// `acknowledgeOwnWrite()` 후에도 *진짜 외부 변경* (changeCount 추가 증가) 은 정상 감지.
    @Test func acknowledgeOwnWrite_StillDetectsLaterExternalChange() async throws {
        let pb = MockPasteboard()
        let repo = InMemoryClipRepository()
        let watcher = makeWatcher(pasteboard: pb, repository: repo)

        // 1. paste 시뮬레이션 + acknowledge.
        pb.changeCount = 10
        pb.setString("paste-out", forType: .string)
        await watcher.acknowledgeOwnWrite()

        // 2. tick — idle.
        await watcher.tick()
        #expect(try await repo.fetchAll().isEmpty)

        // 3. 사용자가 외부에서 다시 ⌘C — changeCount 추가 증가.
        pb.changeCount = 12
        pb.strings[.string] = "external-copy"

        // 4. tick — 정상 감지.
        await watcher.tick()
        #expect(try await repo.fetchAll().count == 1)
    }

    // MARK: - LRU 삭제 시 fileClipService.delete 호출

    @Test func tickDeletesLRUFilesAfterInsert() async throws {
        let pb = MockPasteboard()
        let fileSvc = MockFileClipService()
        let repo = InMemoryClipRepository()
        repo.enforceMaxHistorySizeEnabled = true

        // maxUnpinnedClips 개 이미지 클립 미리 채움 (filePath 있어야 삭제 의미 있음)
        for i in 0..<Constants.maxUnpinnedClips {
            let clip = Clip(
                id: UUID(), type: .image, body: nil,
                filePath: "/mock/\(i).png", isFileExternal: false,
                fileOriginalPath: nil, fileBookmark: nil,
                sourceAppBundleId: nil, isPinned: false,
                createdAt: Date(timeIntervalSinceNow: Double(-i)),
                lastUsedAt: Date(timeIntervalSinceNow: Double(-i))
            )
            try await repo.insert(clip)
        }
        fileSvc.deletedClips.removeAll()  // 위 insert LRU 영향 제거

        // 새 텍스트 클립 insert → LRU 1개 삭제 발생
        pb.changeCount = 1
        pb.setString("overflow", forType: .string)
        let watcher = makeWatcher(pasteboard: pb, fileClipService: fileSvc, repository: repo)
        await watcher.tick()

        #expect(fileSvc.deletedClips.count >= 1)
    }
}
