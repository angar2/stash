// 핀 명칭 / 값 수정 / 빈 순번 새 핀 생성 — **실제 GRDB** 경로 검증 (TASK-098 fix-4)
//
// InMemoryClipRepository mock 은 dedup·컬럼 매핑·raw SQL 바인딩을 재현하지 않는다.
// 그래서 mock 테스트는 통과하는데 실기에서 저장이 안 되는 상황이 실제로 발생했다.
// 본 스위트는 temp 디렉토리에 진짜 SQLite 파일을 만들어 프로덕션 repository 로 검증한다.
import Testing
import Foundation
import GRDB
@testable import stash

@Suite("핀 명칭·값·생성 — 실제 GRDB 경로 (TASK-098)")
struct PinAliasGRDBTests {

    private func makeRepo() throws -> (GRDBClipRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("stash.sqlite")
        return (try GRDBClipRepository(dbPath: dbPath), tempDir)
    }

    private func makeText(_ body: String, pinned: Bool = false, pinnedAt: Date? = nil, alias: String? = nil) -> Clip {
        let now = Date()
        return Clip(
            id: UUID(), type: .text, body: body, filePath: nil, isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil, sourceAppBundleId: nil,
            isPinned: pinned, createdAt: now, lastUsedAt: now, pinnedAt: pinnedAt,
            filePathsJson: nil, pinAlias: alias
        )
    }

    @Test("V6 마이그레이션 — pin_alias 컬럼이 실제로 생성된다")
    func migrationAddsColumn() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = repo

        let dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("stash.sqlite").path)
        let columns = try await dbQueue.read { db in
            try db.columns(in: "clips").map(\.name)
        }
        #expect(columns.contains("pin_alias"))
    }

    @Test("insert — isPinned/pinnedAt/pinAlias 가 그대로 저장된다 (신규 핀 생성 경로의 토대)")
    func insertPersistsPinFields() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date()
        let clip = makeText("새 핀 본문", pinned: true, pinnedAt: now, alias: "내 템플릿")
        _ = try await repo.insert(clip)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        let saved = try #require(all.first)
        #expect(saved.body == "새 핀 본문")
        #expect(saved.isPinned == true)
        #expect(saved.pinnedAt != nil)
        #expect(saved.pinAlias == "내 템플릿")
    }

    @Test("setPinAlias — raw SQL UUID 바인딩이 실제로 row 를 잡는다 (설정/해제)")
    func setPinAliasBinding() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let clip = makeText("body", pinned: true, pinnedAt: Date())
        _ = try await repo.insert(clip)

        try await repo.setPinAlias(id: clip.id, alias: "인증 헤더")
        #expect(try await repo.fetchAll().first?.pinAlias == "인증 헤더")

        try await repo.setPinAlias(id: clip.id, alias: nil)
        #expect(try await repo.fetchAll().first?.pinAlias == nil)
    }

    // MARK: - 자리(pin_slot) — 검수 정정

    @Test("V7 마이그레이션 — 기존 핀에 표시 순서대로 1..N 자리가 배정된다 (업데이트 후 조합 대상 유지)")
    func migrationBackfillsPinSlots() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbQueue = try DatabaseQueue(path: tempDir.appendingPathComponent("stash.sqlite").path)

        // ① V6 까지만 적용된 *업데이트 이전* DB 를 만든다. (Clip 레코드로 넣으면 아직 없는 pin_slot 을 쓰므로 raw SQL 사용.)
        var old = DatabaseMigrator()
        V1_InitialSchema.register(in: &old)
        V2_DedupSameBody.register(in: &old)
        V3_AddPinnedAt.register(in: &old)
        V4_AddFilePathsJson.register(in: &old)
        V5_AddBodyIndex.register(in: &old)
        V6_AddPinAlias.register(in: &old)
        try old.migrate(dbQueue)

        let base = Date(timeIntervalSince1970: 1_000)
        // 핀 3개를 *꽂은 순서와 다르게* 넣어 정렬 근거가 pinned_at 임을 확인한다. 핀 아닌 행도 하나.
        let rows: [(String, Bool, Date?)] = [
            ("세번째", true,  base.addingTimeInterval(120)),
            ("첫번째", true,  base),
            ("핀아님", false, nil),
            ("두번째", true,  base.addingTimeInterval(60))
        ]
        try await dbQueue.write { db in
            for (body, pinned, pinnedAt) in rows {
                try db.execute(sql: """
                    INSERT INTO clips (id, type, body, is_file_external, is_pinned, created_at, last_used_at, pinned_at)
                    VALUES (?, 'text', ?, 0, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, body, pinned, base, base, pinnedAt])
            }
        }

        // ② V7 적용 = 앱 업데이트.
        var new = DatabaseMigrator()
        GRDBClipRepository.registerAllMigrations(in: &new)
        try new.migrate(dbQueue)

        let slots = try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT body, pin_slot FROM clips ORDER BY pin_slot")
                .map { ($0["body"] as String?, $0["pin_slot"] as Int?) }
        }
        // 핀은 표시 순서(pinned_at 오름차순) 그대로 1·2·3 — 업데이트 직후 조합이 가리키는 대상이 바뀌지 않는다.
        #expect(slots.filter { $0.1 != nil }.map { ($0.0, $0.1) }.map { "\($0.0 ?? "")\($0.1 ?? 0)" }
                == ["첫번째1", "두번째2", "세번째3"])
        // 핀이 아닌 행은 자리를 받지 않는다.
        #expect(slots.first { $0.0 == "핀아님" }?.1 == nil)
    }

    @Test("togglePin — 해제하면 **그 자리만** 비고 다른 핀 자리는 그대로 (핵심 회귀 방어)")
    func togglePinClearsOnlyItsOwnSlot() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = makeText("A"), b = makeText("B"), c = makeText("C")
        for clip in [a, b, c] { _ = try await repo.insert(clip) }
        for clip in [a, b, c] { try await repo.togglePin(id: clip.id) }
        var all = try await repo.fetchAll()
        #expect(all.first { $0.id == a.id }?.pinSlot == 1)
        #expect(all.first { $0.id == b.id }?.pinSlot == 2)
        #expect(all.first { $0.id == c.id }?.pinSlot == 3)

        try await repo.togglePin(id: b.id)   // 2번 해제
        all = try await repo.fetchAll()
        #expect(all.first { $0.id == a.id }?.pinSlot == 1)   // 그대로
        #expect(all.first { $0.id == b.id }?.pinSlot == nil) // 자리 비움
        #expect(all.first { $0.id == c.id }?.pinSlot == 3)   // **당겨지지 않는다**

        // 다음 핀은 빈 2번 자리를 채운다.
        let d = makeText("D")
        _ = try await repo.insert(d)
        try await repo.togglePin(id: d.id)
        #expect(try await repo.fetchAll().first { $0.id == d.id }?.pinSlot == 2)
    }

    @Test("pinAtSlot — 지정 자리에 꽂고, 이미 찬 자리·범위 밖은 거부")
    func pinAtSlotBehavior() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = makeText("A"), b = makeText("B")
        for clip in [a, b] { _ = try await repo.insert(clip) }

        #expect(try await repo.pinAtSlot(id: a.id, slot: 7) == true)
        #expect(try await repo.fetchAll().first { $0.id == a.id }?.pinSlot == 7)
        // 같은 자리 재요청은 거부 (다른 클립)
        #expect(try await repo.pinAtSlot(id: b.id, slot: 7) == false)
        #expect(try await repo.fetchAll().first { $0.id == b.id }?.isPinned == false)
        // 범위 밖
        #expect(try await repo.pinAtSlot(id: b.id, slot: 0) == false)
        #expect(try await repo.pinAtSlot(id: b.id, slot: Constants.maxPinnedClips + 1) == false)
    }

    @Test("togglePin — 핀 해제 시 pin_alias 가 실제 DB 에서 NULL 이 된다 (검수 정정)")
    func togglePinClearsAliasOnUnpin() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let clip = makeText("Bearer abc", pinned: true, pinnedAt: Date(), alias: "인증 헤더")
        _ = try await repo.insert(clip)

        // 해제 → 명칭 컬럼이 NULL. row·값은 그대로 남는다 (삭제가 아니다).
        try await repo.togglePin(id: clip.id)
        let dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("stash.sqlite").path)
        let row = try await dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT is_pinned, pin_alias, body FROM clips WHERE id = ?", arguments: [clip.id])
        }
        let unwrapped = try #require(row)
        #expect((unwrapped["is_pinned"] as Int64?) == 0)
        #expect((unwrapped["pin_alias"] as String?) == nil)
        #expect((unwrapped["body"] as String?) == "Bearer abc")

        // 재고정해도 옛 명칭이 되살아나지 않는다.
        try await repo.togglePin(id: clip.id)
        let after = try await repo.fetchAll().first { $0.id == clip.id }
        #expect(after?.isPinned == true)
        #expect(after?.pinAlias == nil)
    }

    @Test("updateBody — 본문만 바뀌고 last_used_at 은 불변")
    func updateBodyKeepsLastUsedAt() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let clip = makeText("before", pinned: true, pinnedAt: Date())
        _ = try await repo.insert(clip)
        let before = try #require(try await repo.fetchAll().first?.lastUsedAt)

        let applied = try await repo.updateBody(id: clip.id, body: "after\n둘째 줄")
        #expect(applied == true)

        let saved = try #require(try await repo.fetchAll().first)
        #expect(saved.body == "after\n둘째 줄")
        #expect(abs(saved.lastUsedAt.timeIntervalSince(before)) < 0.001)
    }

    @Test("updateBody — 텍스트 아닌 타입은 거부")
    func updateBodyRejectsNonText() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date()
        let image = Clip(
            id: UUID(), type: .image, body: nil, filePath: "/tmp/a.png", isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil, sourceAppBundleId: nil,
            isPinned: true, createdAt: now, lastUsedAt: now, pinnedAt: now
        )
        _ = try await repo.insert(image)

        #expect(try await repo.updateBody(id: image.id, body: "글자") == false)
        #expect(try await repo.fetchAll().first?.body == nil)
    }

    @Test("dedup — 같은 본문이 이미 있으면 새 row 가 생기지 않는다 (createPinnedClip 이 수습해야 하는 경로)")
    func dedupSkipsNewRow() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await repo.insert(makeText("중복 본문"))            // 핀 아님
        _ = try await repo.insert(makeText("중복 본문", pinned: true, pinnedAt: Date(), alias: "무시됨"))

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        // dedup 은 last_used_at 만 갱신하므로 **isPinned·pinAlias 는 반영되지 않는다** —
        // 그래서 ClipsViewModel.createPinnedClip 이 insert 후 togglePin/setPinAlias 로 따로 채운다.
        #expect(all.first?.isPinned == false)
        #expect(all.first?.pinAlias == nil)
    }

    @Test("createPinnedClip 전체 흐름 — 빈 상태에서 명칭+값 입력 시 실제로 핀이 생긴다")
    @MainActor
    func createPinnedClipEndToEnd() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: MockPasteSynthesizer(),
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc, fileClipService: MockFileClipService())
        await vm.reload()
        #expect(vm.pinnedClips.isEmpty)

        let created = await vm.createPinnedClip(body: "회의록 템플릿 본문", alias: "회의록")
        #expect(created == true)

        #expect(vm.pinnedClips.count == 1)
        let pin = try #require(vm.pinnedClips.first)
        #expect(pin.body == "회의록 템플릿 본문")
        #expect(pin.pinAlias == "회의록")
        #expect(pin.isPinned == true)

        // DB 에도 실제로 박혔는지 (viewModel 캐시가 아니라 저장소 확인)
        let persisted = try await repo.fetchAll()
        #expect(persisted.count == 1)
        #expect(persisted.first?.isPinned == true)
        #expect(persisted.first?.pinAlias == "회의록")
    }

    @Test("createPinnedClip — 히스토리에 같은 본문이 있던 경우에도 핀이 된다")
    @MainActor
    func createPinnedClipOverExistingBody() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await repo.insert(makeText("이미 있는 본문"))

        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: MockPasteSynthesizer(),
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc, fileClipService: MockFileClipService())
        await vm.reload()

        let created = await vm.createPinnedClip(body: "이미 있는 본문", alias: "재사용")
        #expect(created == true)
        #expect(vm.pinnedClips.count == 1)
        #expect(vm.pinnedClips.first?.pinAlias == "재사용")

        let persisted = try await repo.fetchAll()
        #expect(persisted.count == 1)        // 새 row 가 아니라 기존 row 재사용
        #expect(persisted.first?.isPinned == true)
    }
}
