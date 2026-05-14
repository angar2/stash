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
        try migrator.migrate(dbQueue)
        Logger.database.info("GRDBClipRepository 초기화 완료 — \(dbPath.lastPathComponent)")
    }

    // MARK: - ClipRepository

    func fetchAll() async throws -> [Clip] {
        Logger.database.debug("fetchAll — 시작")
        let clips = try await dbQueue.read { db in
            try Clip
                .order(Column("is_pinned").desc, Column("last_used_at").desc)
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
                    .order(Column("is_pinned").desc, Column("last_used_at").desc)
                    .limit(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
                    .fetchAll(db)
            }
            return try Clip
                .filter(Column("body").like("%\(query)%"))
                .order(Column("is_pinned").desc, Column("last_used_at").desc)
                .limit(Constants.maxUnpinnedClips + Constants.maxPinnedClips)
                .fetchAll(db)
        }
        Logger.database.debug("search — \(clips.count)개 반환")
        return clips
    }

    func updateLastUsedAt(id: UUID) async throws {
        Logger.database.debug("updateLastUsedAt — id: \(id)")
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET last_used_at = ? WHERE id = ?",
                arguments: [Date(), id.uuidString]
            )
        }
    }

    func togglePin(id: UUID) async throws {
        Logger.database.debug("togglePin — id: \(id)")
        try await dbQueue.write { db in
            guard var clip = try Clip.filter(Column("id") == id.uuidString).fetchOne(db) else { return }
            if !clip.isPinned {
                let pinnedCount = try Clip.filter(Column("is_pinned") == 1).fetchCount(db)
                if pinnedCount >= Constants.maxPinnedClips {
                    throw DatabaseError.pinLimitReached
                }
            }
            clip.isPinned.toggle()
            try clip.update(db)
            Logger.database.debug("togglePin — isPinned: \(clip.isPinned)")
        }
    }

    @discardableResult
    func delete(id: UUID) async throws -> Clip? {
        Logger.database.debug("delete — id: \(id)")
        return try await dbQueue.write { db in
            guard let clip = try Clip.filter(Column("id") == id.uuidString).fetchOne(db) else {
                Logger.database.debug("delete — id 없음")
                return nil
            }
            try clip.delete(db)
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
            try migrator.migrate(newQueue)
            dbQueue = newQueue
            Logger.database.info("recoverFromCorruption 완료 — 백업: \(backupPath)")
        } catch {
            Logger.database.error("recoverFromCorruption 실패: \(error)")
        }
    }

    // MARK: - Private helpers

    private func performInsert(_ clip: Clip, in db: Database) throws {
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
