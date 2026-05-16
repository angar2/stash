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
        let deleted = try await dbQueue.write { db in
            try self.performInsert(clip, in: db)
            return try self.enforceMaxHistorySize(in: db)
        }
        Logger.database.debug("insert — LRU 정리 \(deleted.count)개 삭제")
        return deleted
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

    private func performInsert(_ clip: Clip, in db: Database) throws {
        // TASK-019 — 동일 (type, body) 텍스트 클립 dedup. 기존 row 의 last_used_at 갱신 + 새 row 추가 X.
        // image / file 은 file_path UUID 라 자연 중복 X — dedup 안 함.
        if clip.type == .text, let body = clip.body {
            if let existingId = try UUID.fetchOne(
                db,
                sql: "SELECT id FROM clips WHERE type = ? AND body = ? LIMIT 1",
                arguments: [clip.type.rawValue, body]
            ) {
                try db.execute(
                    sql: "UPDATE clips SET last_used_at = ? WHERE id = ?",
                    arguments: [clip.lastUsedAt, existingId]
                )
                Logger.database.debug("performInsert — dedup hit, updated last_used_at for existing id: \(existingId)")
                return
            }
        }
        try clip.insert(db)
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
