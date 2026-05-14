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

    // MARK: - 이미지 클립

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
        #expect(fileSvc.savedFiles.count == 1)
    }

    // MARK: - 파일 URL 클립

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
