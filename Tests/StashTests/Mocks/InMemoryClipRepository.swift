// ClipRepository in-memory mock — 테스트 타깃 전용 (DB 없이 ClipRepository 주입 가능, @unchecked Sendable)
@testable import stash
import Foundation

final class InMemoryClipRepository: ClipRepository, @unchecked Sendable {
    private var clips: [Clip] = []
    var enforceMaxHistorySizeEnabled: Bool = true
    /// TASK-061 — `search(query:)` 진입 카운터. 디바운스 동작 단위 테스트 프록시 메트릭.
    var searchCallCount: Int = 0

    func fetchAll() async throws -> [Clip] {
        // TASK-019 fix 4차 — 정렬 룰 `last_used_at DESC` 만 (`is_pinned DESC` 제거). GRDBClipRepository 정합.
        Array(
            clips
                .sorted { $0.lastUsedAt > $1.lastUsedAt }
                .prefix(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
        )
    }

    /// TASK-100 — 핀 제외 개수. `fetchAll` 과 달리 보관 한도로 자르지 않는다 (한도 판정의 비교 기준이라
    /// 한도로 자르면 자기 자신을 기준 삼는 꼴이 된다).
    func unpinnedCount() async throws -> Int {
        clips.filter { !$0.isPinned }.count
    }

    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip] {
        // TASK-019 fix 5차 — 동일 (type=text, body) dedup. 기존 row 의 lastUsedAt 갱신 + 새 row 추가 X.
        if clip.type == .text, let body = clip.body,
           let existingIdx = clips.firstIndex(where: { $0.type == .text && $0.body == body }) {
            clips[existingIdx].lastUsedAt = clip.lastUsedAt
            return [clip]  // TASK-023 회귀 (f) — text dedup hit 시도 새 clip cleanup 반환 (text 는 disk 파일 X라 noop, 일관성 위해).
        }
        // TASK-026 — 다중 파일 묶음 (F 케이스) dedup by file_paths_json (단일 정합).
        if clip.type == .file, let json = clip.filePathsJson,
           let existingIdx = clips.firstIndex(where: { $0.type == .file && $0.filePathsJson == json }) {
            clips[existingIdx].lastUsedAt = clip.lastUsedAt
            return [clip]  // 새 clip 의 entry 카피본 cleanup 대상.
        }
        // TASK-023 회귀 (f) — file / 이미지 파일 (C 케이스) dedup by fileOriginalPath.
        if (clip.type == .file || clip.type == .image),
           let originalPath = clip.fileOriginalPath,
           let existingIdx = clips.firstIndex(where: { $0.type == clip.type && $0.fileOriginalPath == originalPath }) {
            clips[existingIdx].lastUsedAt = clip.lastUsedAt
            return [clip]  // 새 clip 의 carbon 카피본 cleanup 대상.
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

    /// TASK-103 — 검색 대상은 본문 + 파일 원본 경로 + 묶음 항목 원본 경로 (`GRDBClipRepository` 정합).
    /// 내부 보관 복사본 경로(`filePath`)는 대상 아님. 문자열 포함 대조라 와일드카드 개념 자체가 없다
    /// (실제 구현의 `!` 이스케이프는 SQL LIKE 한정 — 여기서는 이미 글자 그대로 매칭된다).
    func search(query: String) async throws -> [Clip] {
        searchCallCount += 1
        if query.isEmpty { return try await fetchAll() }
        let matched = clips.filter { clip in
            if clip.body?.localizedCaseInsensitiveContains(query) == true { return true }
            if clip.fileOriginalPath?.localizedCaseInsensitiveContains(query) == true { return true }
            return clip.fileEntries?.contains {
                $0.originalPath.localizedCaseInsensitiveContains(query)
            } == true
        }
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
        // TASK-098 검수 정정 — 자리 배정/해제 (GRDBClipRepository 정합).
        // 켜기 = 가장 낮은 빈 자리 / 해제 = 그 자리만 비움 (다른 핀 자리 불변).
        if !clips[index].isPinned {
            let occupied = Set(clips.filter { $0.isPinned }.compactMap(\.pinSlot))
            guard let slot = (1...Constants.maxPinnedClips).first(where: { !occupied.contains($0) }) else {
                throw DatabaseError.pinLimitReached
            }
            clips[index].pinSlot = slot
        } else {
            clips[index].pinSlot = nil
        }
        clips[index].isPinned.toggle()
        // TASK-019 — 핀 시점 기록 (GRDBClipRepository 정합).
        clips[index].pinnedAt = clips[index].isPinned ? Date() : nil
        // TASK-098 검수 정정 — 핀 해제 시 명칭도 초기화 (GRDBClipRepository 정합).
        // 핀을 켜는 방향에서는 건드리지 않는다 (`createPinnedClip` 경로 보호).
        if !clips[index].isPinned {
            clips[index].pinAlias = nil
        }
    }

    /// TASK-098 검수 정정 — 지정 자리에 핀 (GRDBClipRepository 정합).
    @discardableResult
    func pinAtSlot(id: UUID, slot: Int) async throws -> Bool {
        guard slot >= 1, slot <= Constants.maxPinnedClips else { return false }
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        if clips[index].isPinned, clips[index].pinSlot == slot { return true }
        let occupied = Set(clips.filter { $0.isPinned }.compactMap(\.pinSlot))
        guard !occupied.contains(slot) else { return false }
        clips[index].isPinned = true
        clips[index].pinSlot = slot
        clips[index].pinnedAt = Date()
        return true
    }

    /// TASK-098 — 핀 표시용 명칭 저장 (GRDBClipRepository 정합). nil = 해제.
    func setPinAlias(id: UUID, alias: String?) async throws {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].pinAlias = alias
    }

    /// TASK-098 — 본문 수정. 텍스트 타입만 · 빈 값 거부 · `lastUsedAt` 미갱신 (GRDBClipRepository 정합).
    ///
    /// `Clip.body` 가 `let` 이라 부분 수정이 불가능해 통째로 다시 만든다. 그래서 **필드를 하나라도 빠뜨리면
    /// 그 값이 조용히 기본값으로 리셋되는데**, 프로덕션은 `UPDATE clips SET body = ?` 단일 컬럼이라 그런 일이 없다.
    /// (실제로 `pinSlot` 이 빠져 값 수정만으로 자리가 사라지는 상태였다 — 아래 전 필드 나열을 줄이지 말 것.)
    @discardableResult
    func updateBody(id: UUID, body: String) async throws -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        guard clips[index].type == .text else { return false }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let old = clips[index]
        clips[index] = Clip(
            id: old.id,
            type: old.type,
            body: body,
            filePath: old.filePath,
            isFileExternal: old.isFileExternal,
            fileOriginalPath: old.fileOriginalPath,
            fileBookmark: old.fileBookmark,
            sourceAppBundleId: old.sourceAppBundleId,
            isPinned: old.isPinned,
            createdAt: old.createdAt,
            lastUsedAt: old.lastUsedAt,   // 수정은 사용이 아님 — 갱신 X
            pinnedAt: old.pinnedAt,
            filePathsJson: old.filePathsJson,
            pinAlias: old.pinAlias,
            pinSlot: old.pinSlot
        )
        return true
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
