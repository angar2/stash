// TASK-082 Phase 6 — recoverFromCorruption 의 V4 누락 회귀 가드
import Testing
import Foundation
import GRDB
@testable import stash

/// `GRDBClipRepository.recoverFromCorruption` 가 V1/V2/V3/V4 모든 migration 등록하는지 검증.
/// 이전 코드 (TASK-082 Phase 6 이전) 는 V1/V2/V3 만 register → 손상 복구 후 `file_paths_json` 컬럼 없는 빈 DB → multi-file Clip insert 시 SQLite no such column 에러 crash 가능.
@MainActor
@Suite("RecoverFromCorruption — TASK-082 Phase 6 V4 fix", .serialized)
struct RecoverFromCorruptionV4Tests {

    private func tempDbURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recover-test-\(UUID().uuidString).sqlite")
    }

    private func cleanupAround(_ dbURL: URL) {
        try? FileManager.default.removeItem(at: dbURL)
        // recoverFromCorruption 이 생성한 .bak.<timestamp> 파일 모두 정리.
        let folder = dbURL.deletingLastPathComponent()
        let baseName = dbURL.lastPathComponent
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in contents where name.hasPrefix(baseName) && name.contains(".bak.") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    @Test("recoverFromCorruption 후 multi-file Clip insert + select 정상 (V4 등록 검증)")
    func recoverAppliesV4() async throws {
        let dbURL = tempDbURL()
        defer { cleanupAround(dbURL) }

        let repo = try GRDBClipRepository(dbPath: dbURL)

        // recoverFromCorruption 명시 호출 — 정상 DB 에서도 호출 가능 (백업 후 새 빈 DB 생성 + migration 재적용).
        await repo.recoverFromCorruption()

        // V4 등록 검증 — file_paths_json 컬럼이 있는 multi-file Clip insert 가 성공해야 함.
        // 이전 (V4 누락) 시 SQLite 가 *no such column: file_paths_json* 에러 raise.
        let multiFileClip = Clip(
            id: UUID(),
            type: .file,
            body: nil,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: Date(),
            lastUsedAt: Date(),
            pinnedAt: nil,
            filePathsJson: "[{\"originalPath\":\"/tmp/a.txt\",\"filePath\":\"/tmp/a.txt\",\"isFileExternal\":true}]"
        )

        _ = try await repo.insert(multiFileClip)

        let clips = try await repo.fetchAll()
        let inserted = clips.first { $0.id == multiFileClip.id }
        #expect(inserted != nil)
        #expect(inserted?.filePathsJson == multiFileClip.filePathsJson)
    }
}
