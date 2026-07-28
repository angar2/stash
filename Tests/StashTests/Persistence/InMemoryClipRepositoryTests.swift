// InMemoryClipRepository 단위 테스트 — 8 메서드 기본 동작 + LRU/Pin 엣지케이스 (15 케이스)
@testable import stash
import Testing
import Foundation

@Suite("InMemoryClipRepository")
struct InMemoryClipRepositoryTests {

    // MARK: - fetchAll

    @Test func fetchAllEmpty() async throws {
        let repo = InMemoryClipRepository()
        let result = try await repo.fetchAll()
        #expect(result.isEmpty)
    }

    @Test func fetchAllSortedByLastUsedAtIgnoringPin() async throws {
        // TASK-019 fix 4차 — 정렬 룰 `last_used_at DESC` 만. 핀 우선 정렬 제거 (핀 토글 시 행 위치 변동 X).
        let repo = InMemoryClipRepository()
        let pinnedOlder = ClipFixture.makeText(body: "pinned-older", isPinned: true, lastUsedAt: Date(timeIntervalSinceNow: -100))
        let unpinnedNewer = ClipFixture.makeText(body: "unpinned-newer", isPinned: false, lastUsedAt: Date(timeIntervalSinceNow: -10))
        try await repo.insert(pinnedOlder)
        try await repo.insert(unpinnedNewer)
        let result = try await repo.fetchAll()
        // 정렬 = last_used_at DESC 만 → 시간 더 최근인 unpinned 가 first (핀 우선 정렬이었으면 pinned 가 first).
        #expect(result.first?.body == "unpinned-newer")
    }

    @Test func fetchAllSortedByLastUsedAt() async throws {
        let repo = InMemoryClipRepository()
        let older = ClipFixture.makeText(body: "older", lastUsedAt: Date(timeIntervalSinceNow: -100))
        let newer = ClipFixture.makeText(body: "newer", lastUsedAt: Date(timeIntervalSinceNow: -10))
        try await repo.insert(older)
        try await repo.insert(newer)
        let result = try await repo.fetchAll()
        #expect(result.first?.body == "newer")
    }

    // MARK: - insert

    @Test func insertSingleClip() async throws {
        let repo = InMemoryClipRepository()
        let clip = ClipFixture.makeText(body: "hello")
        try await repo.insert(clip)
        let result = try await repo.fetchAll()
        #expect(result.count == 1)
        #expect(result.first?.body == "hello")
    }

    // MARK: - search

    @Test func searchEmptyQueryReturnsAll() async throws {
        let repo = InMemoryClipRepository()
        try await repo.insert(ClipFixture.makeText(body: "alpha"))
        try await repo.insert(ClipFixture.makeText(body: "beta"))
        let result = try await repo.search(query: "")
        #expect(result.count == 2)
    }

    @Test func searchFiltersMatchingBody() async throws {
        let repo = InMemoryClipRepository()
        try await repo.insert(ClipFixture.makeText(body: "hello world"))
        try await repo.insert(ClipFixture.makeText(body: "goodbye"))
        let result = try await repo.search(query: "hello")
        #expect(result.count == 1)
        #expect(result.first?.body == "hello world")
    }

    @Test func searchCaseInsensitive() async throws {
        let repo = InMemoryClipRepository()
        try await repo.insert(ClipFixture.makeText(body: "Hello World"))
        let result = try await repo.search(query: "hello")
        #expect(result.count == 1)
    }

    // MARK: - updateLastUsedAt

    @Test func updateLastUsedAtUpdatesTimestamp() async throws {
        let repo = InMemoryClipRepository()
        let clip = ClipFixture.makeText(lastUsedAt: Date(timeIntervalSinceNow: -1000))
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first!.lastUsedAt
        try await repo.updateLastUsedAt(id: clip.id)
        let after = try await repo.fetchAll().first!.lastUsedAt
        #expect(after > before)
    }

    // MARK: - togglePin

    @Test func togglePinToggles() async throws {
        let repo = InMemoryClipRepository()
        let clip = ClipFixture.makeText(isPinned: false)
        try await repo.insert(clip)
        try await repo.togglePin(id: clip.id)
        let result = try await repo.fetchAll()
        #expect(result.first?.isPinned == true)
    }

    @Test func togglePinLimitThrows() async throws {
        let repo = InMemoryClipRepository()
        for i in 0..<Constants.maxPinnedClips {
            let clip = ClipFixture.makeText(body: "pinned \(i)", isPinned: true)
            try await repo.insert(clip)
        }
        let extra = ClipFixture.makeText(body: "one more", isPinned: false)
        try await repo.insert(extra)
        do {
            try await repo.togglePin(id: extra.id)
            Issue.record("Expected pinLimitReached to be thrown")
        } catch DatabaseError.pinLimitReached {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - delete

    @Test func deleteExistingClipReturnsClip() async throws {
        let repo = InMemoryClipRepository()
        let clip = ClipFixture.makeText(body: "to delete")
        try await repo.insert(clip)
        let deleted = try await repo.delete(id: clip.id)
        #expect(deleted?.id == clip.id)
        let remaining = try await repo.fetchAll()
        #expect(remaining.isEmpty)
    }

    @Test func deleteNonExistingReturnsNil() async throws {
        let repo = InMemoryClipRepository()
        let result = try await repo.delete(id: UUID())
        #expect(result == nil)
    }

    // MARK: - deleteAllExceptPinned

    @Test func deleteAllExceptPinnedRemovesUnpinned() async throws {
        let repo = InMemoryClipRepository()
        try await repo.insert(ClipFixture.makeText(body: "unpinned1"))
        try await repo.insert(ClipFixture.makeText(body: "unpinned2"))
        let deleted = try await repo.deleteAllExceptPinned()
        #expect(deleted.count == 2)
        let remaining = try await repo.fetchAll()
        #expect(remaining.isEmpty)
    }

    @Test func deleteAllExceptPinnedPreservesPinned() async throws {
        let repo = InMemoryClipRepository()
        try await repo.insert(ClipFixture.makeText(body: "pinned", isPinned: true))
        try await repo.insert(ClipFixture.makeText(body: "unpinned"))
        try await repo.deleteAllExceptPinned()
        let remaining = try await repo.fetchAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.isPinned == true)
    }

    // MARK: - 핀 제외 개수 (TASK-100)

    /// 보관 한도는 핀이 아닌 클립에만 적용되므로, 한도 판정의 비교 기준도 *핀 제외* 개수여야 한다.
    /// 전체 개수를 쓰면 핀 개수만큼 하한이 부풀려져 사용자가 한도를 못 내린다.
    @Test("unpinnedCount 는 핀을 세지 않는다")
    func unpinnedCountExcludesPinned() async throws {
        let repo = InMemoryClipRepository()
        for i in 0..<7 {
            try await repo.insert(ClipFixture.makeText(body: "unpinned \(i)"))
        }
        for i in 0..<3 {
            let pinned = ClipFixture.makeText(body: "pinned \(i)")
            try await repo.insert(pinned)
            try await repo.togglePin(id: pinned.id)
        }

        #expect(try await repo.unpinnedCount() == 7)
        #expect(try await repo.fetchAll().count == 10)
    }

    // MARK: - LRU 엣지케이스

    /// TASK-100 — 한도가 고정 200 에서 사용자 설정으로 바뀌었다. 본 테스트는 *그때그때의 한도* 를 기준으로
    /// 정리가 도는지 확인한다 (설정값을 직접 건드리지 않는다 — 공유 UserDefaults 에 쓰면 병렬 스위트와 간섭한다).
    @Test func insertExceedingLimitTrimsOldest() async throws {
        let repo = InMemoryClipRepository()
        let limit = Constants.maxUnpinnedClips
        for i in 0..<limit {
            let clip = ClipFixture.makeText(
                body: "clip \(i)",
                lastUsedAt: Date(timeIntervalSinceNow: Double(i))
            )
            try await repo.insert(clip)
        }
        let oldest = ClipFixture.makeText(
            body: "oldest",
            lastUsedAt: Date(timeIntervalSinceNow: -9999)
        )
        repo.enforceMaxHistorySizeEnabled = true
        try await repo.insert(oldest)

        let result = try await repo.fetchAll()
        #expect(result.count == limit)
        #expect(result.allSatisfy { $0.body != "oldest" })
    }

    @Test func insertWithLRUDisabledNoTrim() async throws {
        let repo = InMemoryClipRepository()
        repo.enforceMaxHistorySizeEnabled = false
        let limit = Constants.maxUnpinnedClips + 5
        for i in 0..<limit {
            try await repo.insert(ClipFixture.makeText(body: "clip \(i)"))
        }
        // fetchAll limits at maxUnpinnedClips + maxPinnedClips — count is capped by fetch
        // but underlying storage should have all items (no LRU trim)
        let deleted = try await repo.deleteAllExceptPinned()
        #expect(deleted.count == limit)
    }

    // MARK: - TASK-023 회귀 (f) — file/image dedup by fileOriginalPath

    /// 동일 fileOriginalPath 인 file 클립 두 번 insert → DB row 1개. 두 번째 시도의 새 clip 은 cleanup 반환에 포함.
    @Test func insertDedupsFileClipWithSameOriginalPath() async throws {
        let repo = InMemoryClipRepository()
        let originalPath = "/Users/zeke/Documents/report.pdf"
        let first = makeFileClipFixture(filePath: "/clips/UUID-1.pdf", originalPath: originalPath, lastUsedAt: Date(timeIntervalSinceNow: -100))
        let second = makeFileClipFixture(filePath: "/clips/UUID-2.pdf", originalPath: originalPath, lastUsedAt: Date(timeIntervalSinceNow: -10))

        try await repo.insert(first)
        let cleanup = try await repo.insert(second)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.fileOriginalPath == originalPath)
        // 두 번째 시도의 새 clip (internal 카피본 path UUID-2) 가 cleanup 반환에 포함 — orphan 디스크 정리 대상.
        #expect(cleanup.contains { $0.filePath == "/clips/UUID-2.pdf" })
    }

    /// 동일 fileOriginalPath 인 image 클립 (C 케이스) 두 번 insert → DB row 1개.
    @Test func insertDedupsImageClipWithSameOriginalPath() async throws {
        let repo = InMemoryClipRepository()
        let originalPath = "/Users/zeke/Downloads/photo.png"
        let first = makeImageClipFixture(filePath: "/clips/IMG-1.png", originalPath: originalPath, lastUsedAt: Date(timeIntervalSinceNow: -100))
        let second = makeImageClipFixture(filePath: "/clips/IMG-2.png", originalPath: originalPath, lastUsedAt: Date(timeIntervalSinceNow: -10))

        try await repo.insert(first)
        let cleanup = try await repo.insert(second)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.fileOriginalPath == originalPath)
        #expect(cleanup.contains { $0.filePath == "/clips/IMG-2.png" })
    }

    /// 메모리 비트맵 image 클립 (fileOriginalPath = nil, B 케이스) 두 번 insert → DB row 2개 (기존 동작 유지).
    @Test func insertDoesNotDedupMemoryBitmapImageClips() async throws {
        let repo = InMemoryClipRepository()
        let first = makeImageClipFixture(filePath: "/clips/IMG-1.png", originalPath: nil, lastUsedAt: Date(timeIntervalSinceNow: -100))
        let second = makeImageClipFixture(filePath: "/clips/IMG-2.png", originalPath: nil, lastUsedAt: Date(timeIntervalSinceNow: -10))

        try await repo.insert(first)
        try await repo.insert(second)

        let all = try await repo.fetchAll()
        #expect(all.count == 2)
    }

    /// dedup hit 시 기존 row 의 lastUsedAt 가 두 번째 시도 값으로 갱신.
    @Test func insertDedupHitUpdatesLastUsedAtToNewValue() async throws {
        let repo = InMemoryClipRepository()
        let originalPath = "/Users/zeke/Downloads/photo.png"
        let oldTime = Date(timeIntervalSinceNow: -1000)
        let newTime = Date(timeIntervalSinceNow: -10)
        let first = makeImageClipFixture(filePath: "/clips/IMG-1.png", originalPath: originalPath, lastUsedAt: oldTime)
        let second = makeImageClipFixture(filePath: "/clips/IMG-2.png", originalPath: originalPath, lastUsedAt: newTime)

        try await repo.insert(first)
        try await repo.insert(second)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        // 기존 row 의 lastUsedAt 가 newTime 으로 갱신됨 (1초 이내 허용).
        let delta = abs(all.first!.lastUsedAt.timeIntervalSince(newTime))
        #expect(delta < 1.0)
    }

    // MARK: - TASK-023 fixture helpers

    private func makeFileClipFixture(filePath: String, originalPath: String, lastUsedAt: Date) -> Clip {
        Clip(
            id: UUID(), type: .file, body: nil,
            filePath: filePath, isFileExternal: false,
            fileOriginalPath: originalPath, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: false,
            createdAt: Date(), lastUsedAt: lastUsedAt
        )
    }

    private func makeImageClipFixture(filePath: String, originalPath: String?, lastUsedAt: Date) -> Clip {
        Clip(
            id: UUID(), type: .image, body: nil,
            filePath: filePath, isFileExternal: false,
            fileOriginalPath: originalPath, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: false,
            createdAt: Date(), lastUsedAt: lastUsedAt
        )
    }
}
