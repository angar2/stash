// ClipRepository in-memory mock — 테스트 타깃 전용 (DB 없이 ClipRepository 주입 가능, @unchecked Sendable)
@testable import stash
import Foundation

final class InMemoryClipRepository: ClipRepository, @unchecked Sendable {
    private var clips: [Clip] = []
    var enforceMaxHistorySizeEnabled: Bool = true

    func fetchAll() async throws -> [Clip] {
        Array(
            clips
                .sorted {
                    if $0.isPinned != $1.isPinned { return $0.isPinned }
                    return $0.lastUsedAt > $1.lastUsedAt
                }
                .prefix(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
        )
    }

    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip] {
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
        return matched.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.lastUsedAt > $1.lastUsedAt
        }
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
