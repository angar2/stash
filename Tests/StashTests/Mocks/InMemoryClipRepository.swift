// ClipRepository in-memory mock — 테스트 타깃 전용 (DB 없이 ClipRepository 주입 가능, @unchecked Sendable)
@testable import stash
import Foundation

final class InMemoryClipRepository: ClipRepository, @unchecked Sendable {
    private var clips: [Clip] = []
    var enforceMaxHistorySizeEnabled: Bool = true

    func fetchAll() async throws -> [Clip] {
        // TASK-019 fix 4차 — 정렬 룰 `last_used_at DESC` 만 (`is_pinned DESC` 제거). GRDBClipRepository 정합.
        Array(
            clips
                .sorted { $0.lastUsedAt > $1.lastUsedAt }
                .prefix(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
        )
    }

    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip] {
        // TASK-019 fix 5차 — 동일 (type=text, body) dedup. 기존 row 의 lastUsedAt 갱신 + 새 row 추가 X. image/file 은 dedup 안 함.
        if clip.type == .text, let body = clip.body,
           let existingIdx = clips.firstIndex(where: { $0.type == .text && $0.body == body }) {
            clips[existingIdx].lastUsedAt = clip.lastUsedAt
            return []
        }
        clips.append(clip)
        guard enforceMaxHistorySizeEnabled else { return [] }
        let unpinned = clips.filter { !$0.isPinned }.sorted { $0.lastUsedAt < $1.lastUsedAt }
        let excess = max(0, unpinned.count - Constants.maxUnpinnedClips)
        guard excess > 0 else { return [] }
        let toDelete = Array(unpinned.prefix(excess))
        clips.removeAll { c in toDelete.contains { $0.id == c.id } }
        return toDelete
    }

    func search(query: String) async throws -> [Clip] {
        if query.isEmpty { return try await fetchAll() }
        let matched = clips.filter { $0.body?.localizedCaseInsensitiveContains(query) == true }
        // TASK-019 fix 4차 — 정렬 룰 `last_used_at DESC` 만 (`is_pinned DESC` 제거).
        return matched.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    func updateLastUsedAt(id: UUID) async throws {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].lastUsedAt = Date()
    }

    func togglePin(id: UUID) async throws {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        if !clips[index].isPinned {
            let pinnedCount = clips.filter { $0.isPinned }.count
            if pinnedCount >= Constants.maxPinnedClips {
                throw DatabaseError.pinLimitReached
            }
        }
        clips[index].isPinned.toggle()
        // TASK-019 — 핀 시점 기록 (GRDBClipRepository 정합).
        clips[index].pinnedAt = clips[index].isPinned ? Date() : nil
    }

    @discardableResult
    func delete(id: UUID) async throws -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        return clips.remove(at: index)
    }

    @discardableResult
    func deleteAllExceptPinned() async throws -> [Clip] {
        let toDelete = clips.filter { !$0.isPinned }
        clips.removeAll { !$0.isPinned }
        return toDelete
    }

    func recoverFromCorruption() async {
        clips = []
    }
}
