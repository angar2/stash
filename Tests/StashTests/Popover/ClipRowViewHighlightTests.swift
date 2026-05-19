// ClipRowView.highlightedAttributedString 순수 함수 검증 — 검색어 매칭 강조 (TASK-035)
// 매칭 정책: 대소문자 무시 / 다중 매칭 / 빈 query 강조 미적용 / 한국어 정합 / mono 베이스 폰트 정합
@testable import stash
import Testing
import SwiftUI

@Suite("ClipRowView — search match highlight")
@MainActor
struct ClipRowViewHighlightTests {

    // MARK: - Helpers

    /// 매칭 강조 run 필터 — foregroundColor == searchMatchForeground 인 run 만 반환.
    private func highlightedRuns(_ attrString: AttributedString) -> [AttributedString.Runs.Run] {
        attrString.runs.filter { $0.foregroundColor == DesignTokens.Colors.searchMatchForeground }
    }

    /// 강조 run 의 문자열 내용 추출.
    private func highlightedSubstrings(_ attrString: AttributedString) -> [String] {
        highlightedRuns(attrString).map { String(attrString[$0.range].characters) }
    }

    // MARK: - Tests

    @Test("빈 query — 강조 run 0개, 베이스 색상만")
    func emptyQuery() {
        let result = ClipRowView.highlightedAttributedString(
            "Hello World",
            query: "",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedRuns(result).isEmpty)
        // 전체가 베이스 (labelPrimary) 색상으로 한 run
        let baseRuns = result.runs.filter { $0.foregroundColor == DesignTokens.Colors.labelPrimary }
        #expect(baseRuns.count == 1)
    }

    @Test("매칭 없음 — 강조 run 0개")
    func noMatch() {
        let result = ClipRowView.highlightedAttributedString(
            "Hello World",
            query: "foo",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedRuns(result).isEmpty)
    }

    @Test("단일 매칭 — 'World' 강조 1개")
    func singleMatch() {
        let result = ClipRowView.highlightedAttributedString(
            "Hello World",
            query: "World",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedSubstrings(result) == ["World"])
    }

    @Test("대소문자 무시 — 'world' 검색이 'World' 매치, 원본 케이스 보존")
    func caseInsensitiveMatch() {
        let result = ClipRowView.highlightedAttributedString(
            "Hello World",
            query: "world",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedSubstrings(result) == ["World"])
    }

    @Test("다중 매칭 — 'abc' 검색이 3회 출현 모두 강조")
    func multipleMatches() {
        let result = ClipRowView.highlightedAttributedString(
            "abc abc abc",
            query: "abc",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedSubstrings(result) == ["abc", "abc", "abc"])
    }

    @Test("부분 단어 매칭 — 'ell' 검색이 'Hello' 안 'ell' 강조")
    func partialWordMatch() {
        let result = ClipRowView.highlightedAttributedString(
            "Hello",
            query: "ell",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedSubstrings(result) == ["ell"])
    }

    @Test("한국어 매칭 — '클립' 검색이 '안녕하세요 클립보드' 안 매치")
    func koreanMatch() {
        let result = ClipRowView.highlightedAttributedString(
            "안녕하세요 클립보드",
            query: "클립",
            baseFont: DesignTokens.Typography.clipBody
        )
        #expect(highlightedSubstrings(result) == ["클립"])
    }

    @Test("mono 베이스 폰트 — 'commit' 강조 시 semibold weight + mono design 유지")
    func monoBaseFont() {
        let baseFont = DesignTokens.Typography.clipBodyMono
        let result = ClipRowView.highlightedAttributedString(
            "git commit",
            query: "commit",
            baseFont: baseFont
        )
        let runs = highlightedRuns(result)
        #expect(runs.count == 1)
        // 강조 run 의 폰트 = 베이스 폰트의 semibold variant 와 동일
        let expectedHighlightFont = baseFont.weight(.semibold)
        #expect(runs.first?.font == expectedHighlightFont)
    }
}
