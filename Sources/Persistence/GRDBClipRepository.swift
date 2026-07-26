// ClipRepository protocol의 GRDB 기반 실제 구현체 — 8 메서드 완전 구현 (DATA-MODEL §6·7 + API-SPEC §3-2 정합)
import Foundation
import GRDB
import OSLog

final class GRDBClipRepository: ClipRepository {
    private nonisolated(unsafe) var dbQueue: DatabaseQueue
    private let dbPath: URL

    init(dbPath: URL) throws {
        self.dbPath = dbPath
        self.dbQueue = try DatabaseQueue(path: dbPath.path)
        var migrator = DatabaseMigrator()
        Self.registerAllMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
        Logger.database.info("GRDBClipRepository 초기화 완료 — \(dbPath.lastPathComponent)")
    }

    /// TASK-082 Phase 6 — migration 등록 단일 진실 소스. init / recoverFromCorruption 양쪽 동일 helper 호출 → V4 누락 회귀 영구 차단.
    /// 신규 Vn 추가 시 본 helper 1줄만 갱신 → 두 호출 경로 자동 정합.
    /// TASK-082 Phase 8 — V5 `(type, body)` 인덱스 추가 (dedup hot-path 대비).
    /// TASK-098 — V6 `pin_alias` 컬럼 추가 (핀 표시용 명칭).
    /// TASK-098 검수 정정 — `internal` 로 연 이유: V7 백필(기존 사용자 자리 배정)을 검증하려면 테스트가
    /// *V6 까지의 DB* 를 만든 뒤 전체 목록을 그대로 적용해봐야 한다. 목록을 테스트에 복제하면 진실 소스가 갈라진다.
    static func registerAllMigrations(in migrator: inout DatabaseMigrator) {
        V1_InitialSchema.register(in: &migrator)
        V2_DedupSameBody.register(in: &migrator)
        V3_AddPinnedAt.register(in: &migrator)
        V4_AddFilePathsJson.register(in: &migrator)
        V5_AddBodyIndex.register(in: &migrator)
        V6_AddPinAlias.register(in: &migrator)
        V7_AddPinSlot.register(in: &migrator)
    }

    // MARK: - ClipRepository

    func fetchAll() async throws -> [Clip] {
        Logger.database.debug("fetchAll — 시작")
        let clips = try await dbQueue.read { db in
            try Clip
                .order(Column("last_used_at").desc)
                .limit(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
                .fetchAll(db)
        }
        Logger.database.debug("fetchAll — \(clips.count)개 반환")
        return clips
    }

    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip] {
        Logger.database.debug("insert — id: \(clip.id)")
        let result = try await dbQueue.write { db -> [Clip] in
            let dedupHit = try self.performInsert(clip, in: db)
            let lruDeleted = try self.enforceMaxHistorySize(in: db)
            // TASK-023 회귀 (f) — dedup hit 시 *원래 새 clip 자체* 도 cleanup 대상 (내부 clips/UUID 카피본 orphan 정리).
            return dedupHit ? lruDeleted + [clip] : lruDeleted
        }
        Logger.database.debug("insert — cleanup \(result.count)개 (LRU + dedup orphan)")
        return result
    }

    func search(query: String) async throws -> [Clip] {
        Logger.database.debug("search — query: \"\(query)\"")
        let clips = try await dbQueue.read { db in
            if query.isEmpty {
                return try Clip
                    .order(Column("last_used_at").desc)
                    .limit(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
                    .fetchAll(db)
            }
            return try Clip
                .filter(Column("body").like("%\(query)%"))
                .order(Column("last_used_at").desc)
                .limit(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
                .fetchAll(db)
        }
        Logger.database.debug("search — \(clips.count)개 반환")
        return clips
    }

    func updateLastUsedAt(id: UUID) async throws {
        Logger.database.debug("updateLastUsedAt — id: \(id)")
        try await dbQueue.write { db in
            // UUID 그대로 binding — GRDB가 BLOB로 변환해 저장된 BLOB id와 매칭 (uuidString String 비교는 dynamic typing 불일치).
            try db.execute(
                sql: "UPDATE clips SET last_used_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    /// TASK-098 검수 정정 — 현재 점유된 핀 자리 목록. 자리 배정·중복 검사의 단일 근거.
    private static func occupiedSlots(in db: Database) throws -> Set<Int> {
        let slots = try Int.fetchAll(db, sql: "SELECT pin_slot FROM clips WHERE is_pinned = 1 AND pin_slot IS NOT NULL")
        return Set(slots)
    }

    /// TASK-098 검수 정정 — 가장 낮은 빈 자리. 자리가 없으면 nil (= 한도 초과).
    private static func lowestFreeSlot(in db: Database) throws -> Int? {
        let occupied = try occupiedSlots(in: db)
        return (1...Constants.maxPinnedClips).first { !occupied.contains($0) }
    }

    func togglePin(id: UUID) async throws {
        Logger.database.debug("togglePin — id: \(id)")
        try await dbQueue.write { db in
            // UUID 그대로 비교 (BLOB ↔ BLOB) — uuidString 비교는 0 row 매칭 문제 있음.
            guard var clip = try Clip.filter(Column("id") == id).fetchOne(db) else { return }
            if !clip.isPinned {
                let pinnedCount = try Clip.filter(Column("is_pinned") == 1).fetchCount(db)
                if pinnedCount >= Constants.maxPinnedClips {
                    throw DatabaseError.pinLimitReached
                }
                // TASK-098 검수 정정 — 자리(1~10) 배정. 개수 가드를 통과했는데 빈 자리가 없다면
                // 자리 데이터가 어긋난 상태이므로 같은 에러로 막는다 (묵묵히 NULL 자리 핀을 만들지 않는다).
                guard let slot = try Self.lowestFreeSlot(in: db) else {
                    Logger.database.error("togglePin — 빈 자리 없음 (pinnedCount=\(pinnedCount) 인데 slot 여유 X)")
                    throw DatabaseError.pinLimitReached
                }
                clip.pinSlot = slot
            } else {
                // 해제 = **그 자리만 비운다.** 다른 핀의 자리는 건드리지 않는다 (번호·조합 유지).
                clip.pinSlot = nil
            }
            clip.isPinned.toggle()
            // TASK-019 — 핀 시점 기록. isPinned=true 면 now / false 면 nil.
            // TASK-098 — 사이드바 정렬 기준은 `pin_slot` 으로 옮겨갔고 `pinned_at` 은 자리 없는 옛 행의 fallback 으로만 남았다.
            // 기록 방식 자체는 동일하다 (V7 백필도 이 값을 순서 근거로 삼았다).
            clip.pinnedAt = clip.isPinned ? Date() : nil
            // TASK-098 검수 정정 — **핀을 해제하면 명칭도 초기화한다.**
            // 명칭은 *핀에만 있는 개념*(Pin 사이드바·설정 PIN 행에서만 쓰인다)이라 해제 후에도 남겨두면,
            // 한참 뒤 같은 항목을 다시 핀했을 때 잊고 있던 옛 이름이 되살아나 사용자를 놀라게 한다.
            // 값(`body`) 수정은 히스토리 원본을 바꾸는 것이라 해제와 무관하게 유지된다 — 초기화 대상은 명칭뿐이다.
            // 핀을 *켜는* 방향에서는 건드리지 않는다 (`createPinnedClip` 의 insert → togglePin → setPinAlias 순서 보호).
            if !clip.isPinned {
                clip.pinAlias = nil
            }
            try clip.update(db)
            Logger.database.debug("togglePin — isPinned: \(clip.isPinned) slot: \(clip.pinSlot?.description ?? "nil") pinnedAt: \(clip.pinnedAt?.description ?? "nil") pinAlias 초기화: \(!clip.isPinned)")
        }
    }

    /// TASK-098 검수 정정 — **지정한 자리**에 핀을 꽂는다. 설정 `PIN 단축키` 의 빈 행에서 새 핀을 만드는 경로 전용.
    /// `togglePin` 은 가장 낮은 빈 자리를 배정하므로, 사용자가 *5번 행* 을 클릭해 만들었는데 2번에 꽂히는 문제가 생긴다.
    /// - 자리가 이미 점유됐거나 범위(1~10) 밖이면 아무것도 하지 않고 `false` 를 반환한다(호출자가 안내).
    @discardableResult
    func pinAtSlot(id: UUID, slot: Int) async throws -> Bool {
        try await dbQueue.write { db in
            guard slot >= 1, slot <= Constants.maxPinnedClips else {
                Logger.database.info("pinAtSlot 거부 — slot=\(slot) 사유: 범위 밖")
                return false
            }
            guard var clip = try Clip.filter(Column("id") == id).fetchOne(db) else {
                Logger.database.info("pinAtSlot 거부 — id: \(id) 사유: 대상 없음")
                return false
            }
            let occupied = try Self.occupiedSlots(in: db)
            // 이미 그 자리를 쓰는 핀이면 no-op 성공 (같은 상태 요청).
            if clip.isPinned, clip.pinSlot == slot { return true }
            guard !occupied.contains(slot) else {
                Logger.database.info("pinAtSlot 거부 — slot=\(slot) 사유: 이미 점유")
                return false
            }
            clip.isPinned = true
            clip.pinSlot = slot
            clip.pinnedAt = Date()
            try clip.update(db)
            Logger.database.info("pinAtSlot — id: \(id) slot: \(slot)")
            return true
        }
    }

    /// TASK-098 — 핀 표시용 명칭 저장. raw SQL UPDATE 로 `pin_alias` 단일 컬럼만 건드린다
    /// (`clip.update(db)` 는 전 컬럼을 다시 쓰므로 다른 컬럼 회귀 여지가 있다).
    func setPinAlias(id: UUID, alias: String?) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET pin_alias = ? WHERE id = ?",
                arguments: [alias, id]
            )
            let changes = db.changesCount
            Logger.database.info("setPinAlias — id: \(id) 설정: \(alias != nil) 길이: \(alias?.count ?? 0) changes: \(changes)")
        }
    }

    /// TASK-098 — 클립 본문 수정. 텍스트 타입만 · 빈 값 거부 · `last_used_at` 미갱신.
    @discardableResult
    func updateBody(id: UUID, body: String) async throws -> Bool {
        try await dbQueue.write { db in
            guard let clip = try Clip.filter(Column("id") == id).fetchOne(db) else {
                Logger.database.info("updateBody 거부 — id: \(id) 사유: 대상 없음")
                return false
            }
            guard clip.type == .text else {
                Logger.database.info("updateBody 거부 — id: \(id) 사유: 텍스트 아님 (type: \(clip.type.rawValue, privacy: .public))")
                return false
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger.database.info("updateBody 거부 — id: \(id) 사유: 빈 값")
                return false
            }
            // `last_used_at` 을 갱신하지 않는 것이 핵심 — 수정은 사용이 아니므로 히스토리 정렬이 흔들리면 안 된다.
            try db.execute(sql: "UPDATE clips SET body = ? WHERE id = ?", arguments: [body, id])
            Logger.database.info("updateBody — id: \(id) 이전 길이: \(clip.body?.count ?? 0) 이후 길이: \(body.count)")
            return true
        }
    }

    @discardableResult
    func delete(id: UUID) async throws -> Clip? {
        Logger.database.debug("delete — id: \(id)")
        return try await dbQueue.write { db in
            // GRDB가 UUID를 16바이트 BLOB로 저장 — String 비교 (id.uuidString)는 dynamic typing 차이로 0 row 매칭. UUID 그대로 비교 필수 (TASK-016 D-2 root cause).
            guard let clip = try Clip.filter(Column("id") == id).fetchOne(db) else {
                Logger.database.debug("delete — id 없음")
                return nil
            }
            try Clip.filter(Column("id") == id).deleteAll(db)
            Logger.database.debug("delete — 완료")
            return clip
        }
    }

    @discardableResult
    func deleteAllExceptPinned() async throws -> [Clip] {
        Logger.database.debug("deleteAllExceptPinned — 시작")
        return try await dbQueue.write { db in
            let toDelete = try Clip.filter(Column("is_pinned") == 0).fetchAll(db)
            try Clip.filter(Column("is_pinned") == 0).deleteAll(db)
            Logger.database.debug("deleteAllExceptPinned — \(toDelete.count)개 삭제")
            return toDelete
        }
    }

    func recoverFromCorruption() async {
        Logger.database.error("recoverFromCorruption — 시작")
        do {
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupPath = dbPath.path + ".bak.\(timestamp)"
            try dbQueue.close()
            try FileManager.default.copyItem(atPath: dbPath.path, toPath: backupPath)
            try FileManager.default.removeItem(atPath: dbPath.path)
            let newQueue = try DatabaseQueue(path: dbPath.path)
            var migrator = DatabaseMigrator()
            // TASK-082 Phase 6 — `registerAllMigrations` 단일 helper 호출로 변경 (이전 V1/V2/V3 만 register, V4 누락 fix). 손상 복구 후 multi-file insert / select crash 영구 차단.
            Self.registerAllMigrations(in: &migrator)
            try migrator.migrate(newQueue)
            dbQueue = newQueue
            Logger.database.info("recoverFromCorruption 완료 — 백업: \(backupPath)")
        } catch {
            Logger.database.error("recoverFromCorruption 실패: \(error)")
        }
    }

    // MARK: - Private helpers

    /// 반환값: dedup hit 여부 (true 면 새 row 추가 X — caller 가 새 clip 의 disk 파일 cleanup).
    private func performInsert(_ clip: Clip, in db: Database) throws -> Bool {
        // TASK-019 — 동일 (type=text, body) 텍스트 클립 dedup.
        if clip.type == .text, let body = clip.body,
           try dedupByEquality(in: db, type: .text, column: "body", value: body, newLastUsedAt: clip.lastUsedAt) {
            return true
        }
        // TASK-026 — 다중 파일 묶음 (F 케이스) dedup by file_paths_json (JSONEncoder `.sortedKeys` 결정성 보장).
        // 단일 정합 (단일 파일은 file_original_path dedup) — 동일 set 동일 순서 ⌘C 시 dedup hit.
        if clip.type == .file, let json = clip.filePathsJson,
           try dedupByEquality(in: db, type: .file, column: "file_paths_json", value: json, newLastUsedAt: clip.lastUsedAt) {
            return true
        }
        // TASK-023 회귀 (f) — file / 이미지 파일 (C 케이스) dedup by fileOriginalPath (원본 절대 경로 = 원초적 식별자).
        // 메모리 비트맵 (B 케이스 = fileOriginalPath nil) 은 분기 진입 X — 매 캡쳐 별개 row.
        if (clip.type == .file || clip.type == .image), let originalPath = clip.fileOriginalPath,
           try dedupByEquality(in: db, type: clip.type, column: "file_original_path", value: originalPath, newLastUsedAt: clip.lastUsedAt) {
            return true
        }
        try clip.insert(db)
        return false
    }

    /// `(type, <column>) = (type, value)` 매칭되는 기존 row 발견 시 `last_used_at` 만 갱신하고 true 반환. 미매칭 시 false.
    /// dedup helper — text body / file·image fileOriginalPath 양쪽 호출 사이트 공통화 (TASK-023 리팩토링).
    /// 주의: `column` 인자는 *컴파일 타임 상수* 만 박음. 외부 입력 직접 전달 금지 (SQL 인젝션 위험).
    private func dedupByEquality(
        in db: Database,
        type: ClipType,
        column: String,
        value: String,
        newLastUsedAt: Date
    ) throws -> Bool {
        let selectSQL = "SELECT id FROM clips WHERE type = ? AND \(column) = ? LIMIT 1"
        guard let existingId = try UUID.fetchOne(db, sql: selectSQL, arguments: [type.rawValue, value]) else {
            return false
        }
        try db.execute(
            sql: "UPDATE clips SET last_used_at = ? WHERE id = ?",
            arguments: [newLastUsedAt, existingId]
        )
        Logger.database.debug("performInsert — dedup hit (\(type.rawValue), \(column)), updated existing id: \(existingId)")
        return true
    }

    private func enforceMaxHistorySize(in db: Database) throws -> [Clip] {
        let count = try Clip.filter(Column("is_pinned") == 0).fetchCount(db)
        guard count > Constants.maxUnpinnedClips else { return [] }
        let toDelete = try Clip
            .filter(Column("is_pinned") == 0)
            .order(Column("last_used_at").asc)
            .limit(count - Constants.maxUnpinnedClips)
            .fetchAll(db)
        for clip in toDelete {
            try clip.delete(db)
        }
        return toDelete
    }
}
