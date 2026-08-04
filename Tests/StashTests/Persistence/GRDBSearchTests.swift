// 검색 대상 확장(파일 경로) + 와일드카드 문자 처리 단위 테스트 — GRDBClipRepository.search (TASK-103)
@testable import stash
import Testing
import Foundation

/// DATA-MODEL §7 검색 SQL 정책 검증 — 대상 컬럼(#2) / 와일드카드 이스케이프(#6) /
/// 묶음 2차 대조(#7) / 묶음 패턴 경로 구분자(#8) + 기존 정책(#1·#3·#5) 회귀.
///
/// 실제 DB 파일을 임시 폴더에 만들어 검증한다 — 사용자 DB(`AppDataPath.databaseFile()`)는 열지 않는다.
/// 보관 한도는 인스턴스에 주입한다 (공유 UserDefaults 를 쓰면 병렬 실행되는 다른 스위트와 간섭).
@Suite("Search scope & escape — TASK-103")
struct GRDBSearchTests {

    /// 공통 fixture 8건. `lastUsedAt` 은 C1 이 가장 오래되고 C8 이 가장 최근이다 (정렬 검증용).
    private struct Fixture {
        let repo: GRDBClipRepository
        let tempDir: URL
        let c1, c2, c3, c4, c5, c6, c7, c8: Clip
    }

    private static func makeFixture() async throws -> Fixture {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stash-search-scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let repo = try GRDBClipRepository(
            dbPath: tempDir.appendingPathComponent("search.db"),
            historyLimit: { 200 }
        )

        let base = Date()
        func at(_ secondsAgo: Int) -> Date { base.addingTimeInterval(TimeInterval(-secondsAgo)) }

        let c1 = ClipFixture.makeText(body: "50% 할인 쿠폰", lastUsedAt: at(8))
        let c2 = ClipFixture.makeText(body: "보고서 초안", lastUsedAt: at(7))
        let c3 = ClipFixture.makeText(body: "a_b 규칙", lastUsedAt: at(6))
        let c4 = ClipFixture.makeText(body: "axb 규칙", lastUsedAt: at(5))
        let c5 = ClipFixture.makeText(body: "안녕! 반가워", lastUsedAt: at(4))
        let c6 = ClipFixture.makeFile(
            originalPath: "/Users/angari/Documents/보고서/최종.pdf",
            filePath: "/Library/copies/A1B2_최종.pdf",
            lastUsedAt: at(3)
        )
        let c7 = ClipFixture.makeImage(
            filePath: "/Library/copies/screenshot.png",
            originalPath: nil,
            lastUsedAt: at(2)
        )
        let c8 = ClipFixture.makeMultiFile(
            entries: [
                ClipFileEntry(
                    originalPath: "/tmp/원본/file-list.txt",
                    filePath: "/Library/copies/x-file-list.txt",
                    isFileExternal: false
                ),
                ClipFileEntry(
                    originalPath: "/tmp/원본/data.csv",
                    filePath: "/Library/copies/y-data.csv",
                    isFileExternal: false
                )
            ],
            lastUsedAt: at(1)
        )

        for clip in [c1, c2, c3, c4, c5, c6, c7, c8] {
            try await repo.insert(clip)
        }

        return Fixture(repo: repo, tempDir: tempDir, c1: c1, c2: c2, c3: c3, c4: c4, c5: c5, c6: c6, c7: c7, c8: c8)
    }

    private static func cleanUp(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.tempDir)
    }

    // MARK: - 검색 대상 확장 (정책 #2)

    @Test("파일 클립을 파일명으로 찾는다")
    func findsFileClipByFileName() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "최종.pdf")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c6.id)
    }

    @Test("파일 클립을 상위 폴더명으로 찾는다")
    func findsFileClipByParentFolderName() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "Documents")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c6.id)
    }

    @Test("묶음 클립을 항목 파일명으로 찾는다")
    func findsMultiFileClipByEntryFileName() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "data.csv")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c8.id)
    }

    /// 정책 #8 — 묶음 JSON 안에서 `/` 가 `\/` 로 저장되므로 대조 패턴도 그 표기를 따라야 한다.
    @Test("경로 구분자가 든 검색어로 묶음 클립을 찾는다")
    func findsMultiFileClipByQueryWithPathSeparator() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "원본/data")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c8.id)
    }

    /// 정책 #7 — SQL LIKE 만으로는 JSON 열쇠말까지 걸린다. 2차 대조가 이를 걸러내야 한다.
    @Test("묶음 저장 형식의 열쇠말은 매칭되지 않는다")
    func doesNotMatchMultiFileJsonKeys() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "original_path")
        #expect(result.isEmpty, "0건 기대, 실제 \(result.count)건 — JSON 열쇠말 오탐")
    }

    /// 정책 #2 — 내부 보관 복사본 경로는 검색 대상이 아니다.
    @Test("내부 보관 복사본 경로는 검색되지 않는다")
    func doesNotSearchInternalCopyPath() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "Library/copies")
        #expect(result.isEmpty, "0건 기대, 실제 \(result.count)건 — 보관 복사본 경로가 검색됨")
    }

    /// 한계 확인 — 원본 경로도 본문도 없는 이미지 클립은 대조할 문자열이 없다.
    @Test("원본이 없는 이미지 클립은 검색되지 않는다")
    func doesNotFindImageClipWithoutOriginalPath() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "screenshot")
        #expect(result.isEmpty, "0건 기대, 실제 \(result.count)건")
    }

    // MARK: - 와일드카드 문자 처리 (정책 #6)

    @Test("% 는 와일드카드가 아니라 글자 그대로다")
    func percentIsLiteral() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "%")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건 — 전체 반환이면 이스케이프 미적용")
        #expect(result.first?.id == f.c1.id)
    }

    @Test("_ 는 임의 한 글자가 아니라 글자 그대로다")
    func underscoreIsLiteral() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "a_b")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건 — axb 가 섞였으면 이스케이프 미적용")
        #expect(result.first?.id == f.c3.id)
    }

    @Test("이스케이프 문자 자신도 글자 그대로 검색된다")
    func escapeCharacterItselfIsLiteral() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "!")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c5.id)
    }

    // MARK: - 기존 정책 회귀 (#1 substring · #3 대소문자 · #5 빈 쿼리 · 정렬)

    @Test("본문과 파일 경로 양쪽에서 매칭되고 최근 사용순으로 반환된다")
    func matchesBothBodyAndPathOrderedByLastUsed() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "보고서")
        #expect(result.count == 2, "2건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c6.id, "최근 사용순이면 파일 클립이 먼저")
        #expect(result.last?.id == f.c2.id)
    }

    @Test("빈 검색어는 전체 목록을 반환한다")
    func emptyQueryReturnsAll() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "")
        #expect(result.count == 8, "8건 기대, 실제 \(result.count)건")
    }

    @Test("부분 문자열 매칭 정책이 유지된다")
    func substringMatchingRetained() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "보고")
        #expect(result.count == 2, "2건 기대, 실제 \(result.count)건")
    }

    @Test("대소문자 무시 정책이 유지된다")
    func caseInsensitiveRetained() async throws {
        let f = try await Self.makeFixture()
        defer { Self.cleanUp(f) }

        let result = try await f.repo.search(query: "DOCUMENTS")
        #expect(result.count == 1, "1건 기대, 실제 \(result.count)건")
        #expect(result.first?.id == f.c6.id)
    }
}
