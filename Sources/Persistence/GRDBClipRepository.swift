// ClipRepository protocol의 GRDB 기반 실제 구현체 — init + 8 메서드 stub (TASK-004에서 채움)
import Foundation
import GRDB
import OSLog

final class GRDBClipRepository: ClipRepository {
    private let dbQueue: DatabaseQueue

    init(dbPath: URL) throws {
        self.dbQueue = try DatabaseQueue(path: dbPath.path)
        var migrator = DatabaseMigrator()
        V1_InitialSchema.register(in: &migrator)
        try migrator.migrate(dbQueue)
        Logger.database.info("GRDBClipRepository 초기화 완료 — \(dbPath.lastPathComponent)")
    }

    // MARK: - ClipRepository stub (TASK-004에서 구현)

    func fetchAll() async throws -> [Clip] {
        fatalError("TASK-004에서 구현")
    }

    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip] {
        fatalError("TASK-004에서 구현")
    }

    func search(query: String) async throws -> [Clip] {
        fatalError("TASK-004에서 구현")
    }

    func updateLastUsedAt(id: UUID) async throws {
        fatalError("TASK-004에서 구현")
    }

    func togglePin(id: UUID) async throws {
        fatalError("TASK-004에서 구현")
    }

    @discardableResult
    func delete(id: UUID) async throws -> Clip? {
        fatalError("TASK-004에서 구현")
    }

    @discardableResult
    func deleteAllExceptPinned() async throws -> [Clip] {
        fatalError("TASK-004에서 구현")
    }

    func recoverFromCorruption() async {
        fatalError("TASK-004에서 구현")
    }
}
