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

    // MARK: - LRU 엣지케이스

    @Test func insertExceeding200TrimsOldest() async throws {
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
}
