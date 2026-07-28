// 검색 < 50ms (200건 기준) GRDBClipRepository.search() 단위 benchmark (TASK-091 Phase 2)
@testable import stash
import Testing
import Foundation

/// UX-UI §9 + ROADMAP §2-2 *검색 입력 변경 → 결과 갱신 (200건 기준) < 50ms* 임계 검증.
///
/// **측정 영역**: `GRDBClipRepository.search(query:)` 호출 시간 (debounce / SwiftUI render 제외 — 순수 DB query + decode).
/// XCUITest *입력 → row 갱신* wall-clock 측정은 debounce + SwiftUI body 재평가 + accessibility hit testing 등 외부 잡음 큰 영역. 본 benchmark 는 *DB 검색* 자체 시간만 격리 측정.
///
/// 200건 fixture insert + warmup 1 + 5 iter 평균. unique 매칭 query (`#150` ~ `#190`) — body `UITest seed clip #N` 패턴 정합.
@Suite("Search benchmark — TASK-091")
struct SearchBenchmarkTests {

    /// 200건 fixture insert 후 5회 평균 search 시간 < 50ms 검증.
    @Test("200 clips — search query → result < 50ms (5-iter mean)")
    func search200Clips_under50ms() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stash-search-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("bench.db")
        // TASK-100 — 한도를 200 으로 고정해 주입한다. 보관 한도가 사용자 설정이 되면서 기본값(50)으로는
        // 아래 200건 중 150건이 LRU 로 잘려 `#150`~`#190` 매칭이 0건이 된다. 전역 설정을 바꾸는 대신
        // 이 인스턴스에만 한도를 준다 — 공유 키에 쓰면 같은 키를 읽는 다른 스위트와 병렬 실행에서 간섭한다.
        let repo = try GRDBClipRepository(dbPath: dbPath, historyLimit: { 200 })

        // 200건 insert — body `UITest seed clip #N` (N=1~200).
        for i in 1...200 {
            let clip = ClipFixture.makeText(
                body: "UITest seed clip #\(i)",
                lastUsedAt: Date().addingTimeInterval(TimeInterval(-i))
            )
            try await repo.insert(clip)
        }

        // 워밍업 1회 — GRDB statement cache + page cache 채움.
        _ = try await repo.search(query: "#100")

        // 5회 평균 — 매번 unique 매칭 query (50 간격).
        let queries = ["#150", "#160", "#170", "#180", "#190"]
        var deltas: [Double] = []
        for query in queries {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await repo.search(query: query)
            let end = CFAbsoluteTimeGetCurrent()
            let deltaMs = (end - start) * 1000
            deltas.append(deltaMs)
            print(String(format: "[search-bench] query=%@ delta=%.2fms result=%d", query, deltaMs, result.count))
            // unique 매칭 1건 기대 (#150 → body "UITest seed clip #150").
            #expect(result.count == 1, "query=\(query) unique 매칭 1건 기대, 실제 \(result.count)건")
        }

        let avg = deltas.reduce(0, +) / Double(deltas.count)
        print(String(format: "[search-bench] avg-delta=%.2fms (5-iter mean, n=200, debounce-excluded)", avg))

        #expect(avg < 50.0, "200건 search 평균 \(String(format: "%.2f", avg))ms — 50ms 임계 초과")
    }
}
