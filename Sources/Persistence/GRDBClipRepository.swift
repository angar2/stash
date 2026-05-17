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
        V1_InitialSchema.register(in: &migrator)
        V2_DedupSameBody.register(in: &migrator)
        V3_AddPinnedAt.register(in: &migrator)
        try migrator.migrate(dbQueue)
        Logger.database.info("GRDBClipRepository 초기화 완료 — \(dbPath.lastPathComponent)")
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
            }
            clip.isPinned.toggle()
            // TASK-019 — 핀 시점 기록. isPinned=true 면 now / false 면 nil. Pin 사이드바 정렬(최근 핀 우선) 기준.
            clip.pinnedAt = clip.isPinned ? Date() : nil
            try clip.update(db)
            Logger.database.debug("togglePin — isPinned: \(clip.isPinned) pinnedAt: \(clip.pinnedAt?.description ?? "nil")")
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
            V1_InitialSchema.register(in: &migrator)
            V2_DedupSameBody.register(in: &migrator)
            V3_AddPinnedAt.register(in: &migrator)
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
