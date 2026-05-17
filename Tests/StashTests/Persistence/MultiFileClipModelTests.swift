// 다중 파일 묶음 데이터 모델 + V4 마이그레이션 + dedup 단위 테스트 (TASK-026 Phase 1)
import Testing
import Foundation
import GRDB
@testable import stash

@Suite("MultiFileClipModel")
struct MultiFileClipModelTests {

    // MARK: - ClipFileEntry Codable

    @Test("ClipFileEntry Codable round-trip — snake_case 직렬화 (encodeJSON / decodeJSON helper)")
    func clipFileEntryCodableRoundTrip() throws {
        let entry = ClipFileEntry(
            originalPath: "/Users/zeke/photo.png",
            filePath: "/Library/copies/uuid.png",
            isFileExternal: true
        )
        let json = try ClipFileEntry.encodeJSON([entry])
        // snake_case key 확인
        #expect(json.contains("\"original_path\""))
        #expect(json.contains("\"file_path\""))
        #expect(json.contains("\"is_file_external\""))
        // round-trip
        let decoded = ClipFileEntry.decodeJSON(json)
        #expect(decoded?.count == 1)
        #expect(decoded?.first == entry)
    }

    @Test("encodeJSON — `.sortedKeys` 강제로 동일 entries 입력 시 결정적 JSON 출력 (dedup 매칭 정합성)")
    func sortedKeysDeterministic() throws {
        let entries: [ClipFileEntry] = [
            ClipFileEntry(originalPath: "/a", filePath: "/aa", isFileExternal: false),
            ClipFileEntry(originalPath: "/b", filePath: "/bb", isFileExternal: true)
        ]
        let json1 = try ClipFileEntry.encodeJSON(entries)
        let json2 = try ClipFileEntry.encodeJSON(entries)
        #expect(json1 == json2)
    }

    // MARK: - Clip Codable + isMultiFile / fileEntries

    @Test("Clip — filePathsJson nil 시 isMultiFile false / fileEntries nil")
    func clipSingleFileFlags() {
        let single = ClipFixture.makeText()
        #expect(single.isMultiFile == false)
        #expect(single.fileEntries == nil)
    }

    @Test("Clip — filePathsJson 박힘 시 isMultiFile true / fileEntries 정합")
    func clipMultiFileFlags() {
        let entries = [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/a.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/b.png", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/big.mp4", filePath: "/tmp/big.mp4", isFileExternal: true)
        ]
        let clip = ClipFixture.makeMultiFile(entries: entries)
        #expect(clip.isMultiFile == true)
        #expect(clip.fileEntries?.count == 3)
        #expect(clip.fileEntries?[0] == entries[0])
        #expect(clip.fileEntries?[2].isFileExternal == true)
    }

    @Test("Clip — 잘못된 JSON 박힘 시 fileEntries nil 반환 (silent)")
    func clipMultiFileMalformedJson() {
        var clip = ClipFixture.makeMultiFile()
        clip.filePathsJson = "not-a-json"
        #expect(clip.isMultiFile == true)  // != nil 이라 true
        #expect(clip.fileEntries == nil)   // 디코드 실패 → nil
    }

    @Test("Clip Codable round-trip — filePathsJson 박힘 / nil 양쪽")
    func clipCodableRoundTrip() throws {
        let multi = ClipFixture.makeMultiFile()
        let multiData = try JSONEncoder().encode(multi)
        let multiDecoded = try JSONDecoder().decode(Clip.self, from: multiData)
        #expect(multiDecoded.id == multi.id)
        #expect(multiDecoded.filePathsJson == multi.filePathsJson)

        let single = ClipFixture.makeText()
        let singleData = try JSONEncoder().encode(single)
        let singleDecoded = try JSONDecoder().decode(Clip.self, from: singleData)
        #expect(singleDecoded.filePathsJson == nil)
    }

    // MARK: - V4 마이그레이션

    @Test("V4 마이그레이션 — file_paths_json 컬럼 추가 + 기존 row NULL 보존")
    func v4MigrationAddsColumn() throws {
        let tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stash-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempPath) }

        // V1+V2+V3까지 적용된 DB 생성
        let dbQueue = try DatabaseQueue(path: tempPath.path)
        var migrator = DatabaseMigrator()
        V1_InitialSchema.register(in: &migrator)
        V2_DedupSameBody.register(in: &migrator)
        V3_AddPinnedAt.register(in: &migrator)
        try migrator.migrate(dbQueue)

        // V3 DB에 row 1개 박음
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO clips (id, type, body, is_file_external, is_pinned, created_at, last_used_at)
                VALUES ('test-uuid', 'text', 'hello', 0, 0, ?, ?)
            """, arguments: [Date(), Date()])
        }

        // V4 register + 마이그레이션 적용
        V4_AddFilePathsJson.register(in: &migrator)
        try migrator.migrate(dbQueue)

        // 컬럼 추가 검증
        try dbQueue.read { db in
            let columns = try db.columns(in: "clips")
            let names = columns.map { $0.name }
            #expect(names.contains("file_paths_json"))
        }

        // 기존 row file_paths_json = NULL 보존 검증
        try dbQueue.read { db in
            let value: String? = try String.fetchOne(
                db,
                sql: "SELECT file_paths_json FROM clips WHERE id = ?",
                arguments: ["test-uuid"]
            )
            #expect(value == nil)
        }
    }

    // MARK: - dedup (InMemoryClipRepository)

    @Test("InMemoryClipRepository — 동일 file_paths_json 두 번 insert 시 dedup hit")
    func inMemoryDedupHit() async throws {
        let repo = InMemoryClipRepository()
        let entries = [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/a.txt", isFileExternal: false)
        ]
        let first = ClipFixture.makeMultiFile(entries: entries, lastUsedAt: Date(timeIntervalSinceNow: -100))
        let second = ClipFixture.makeMultiFile(entries: entries, lastUsedAt: Date())

        _ = try await repo.insert(first)
        let dedupResult = try await repo.insert(second)

        // dedup hit — 두 번째 clip은 cleanup 반환 + 기존 row last_used_at 갱신
        #expect(dedupResult.count == 1)
        #expect(dedupResult.first?.id == second.id)

        // fetchAll 시 row 1개만 (기존 first id 유지)
        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.id == first.id)
        #expect(all.first?.lastUsedAt == second.lastUsedAt)
    }

    @Test("InMemoryClipRepository — 다른 file_paths_json 시 dedup miss (별개 row)")
    func inMemoryDedupMiss() async throws {
        let repo = InMemoryClipRepository()
        let first = ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/a.txt", isFileExternal: false)
        ])
        let second = ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/b.txt", filePath: "/Library/b.txt", isFileExternal: false)
        ])

        _ = try await repo.insert(first)
        let dedupResult = try await repo.insert(second)

        // dedup miss — second 그대로 박힘, cleanup 0
        #expect(dedupResult.isEmpty)
        let all = try await repo.fetchAll()
        #expect(all.count == 2)
    }
}
