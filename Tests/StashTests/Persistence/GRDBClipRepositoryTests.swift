// GRDBClipRepository 단위 테스트 — PRAGMA integrity_check + recoverFromCorruption (2 케이스)
@testable import stash
import Testing
import Foundation
import GRDB

@Suite("GRDBClipRepository")
struct GRDBClipRepositoryTests {

    @Test func freshDBPassesIntegrityCheck() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("test.db")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = try GRDBClipRepository(dbPath: dbPath)

        let dbQueue = try DatabaseQueue(path: dbPath.path)
        let result = try await dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check")
        }
        #expect(result == "ok")
    }

    @Test func recoverFromCorruptionCreatesBackupAndFreshDB() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("test.db")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = try GRDBClipRepository(dbPath: dbPath)
        let clip = ClipFixture.makeText(body: "before recovery")
        try await repo.insert(clip)

        let beforeCount = try await repo.fetchAll().count
        #expect(beforeCount == 1)

        await repo.recoverFromCorruption()

        let afterCount = try await repo.fetchAll().count
        #expect(afterCount == 0)

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let backups = files.filter { $0.contains(".bak.") }
        #expect(!backups.isEmpty)
    }
}
