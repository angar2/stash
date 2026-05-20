// ClipRowView.badgeText 순수 함수 검증 — 다중 파일 N 배지 표시 텍스트 결정 (TASK-042)
// 분기: count<=0 nil / 1≤count<100 "\(count)" / count>=100 "99+" 캡
@testable import stash
import Testing

@Suite("ClipRowView — multi-file badge text")
struct ClipRowViewBadgeTextTests {

    @Test("count 0 — nil (배지 미표시)")
    func zeroCount() {
        #expect(ClipRowView.badgeText(for: 0) == nil)
    }

    @Test("count 음수 — nil (가드)")
    func negativeCount() {
        #expect(ClipRowView.badgeText(for: -1) == nil)
        #expect(ClipRowView.badgeText(for: -100) == nil)
    }

    @Test("1자리 — 그대로 표시")
    func singleDigit() {
        #expect(ClipRowView.badgeText(for: 1) == "1")
        #expect(ClipRowView.badgeText(for: 5) == "5")
        #expect(ClipRowView.badgeText(for: 9) == "9")
    }

    @Test("자릿수 경계 — 10 → \"10\"")
    func twoDigitBoundary() {
        #expect(ClipRowView.badgeText(for: 10) == "10")
    }

    @Test("2자리 — 그대로 표시")
    func twoDigit() {
        #expect(ClipRowView.badgeText(for: 25) == "25")
        #expect(ClipRowView.badgeText(for: 84) == "84")
        #expect(ClipRowView.badgeText(for: 99) == "99")
    }

    @Test("캡 경계 — 100 → \"99+\"")
    func capBoundary() {
        #expect(ClipRowView.badgeText(for: 100) == "99+")
    }

    @Test("100+ — \"99+\" 캡")
    func capOverflow() {
        #expect(ClipRowView.badgeText(for: 150) == "99+")
        #expect(ClipRowView.badgeText(for: 250) == "99+")
        #expect(ClipRowView.badgeText(for: 9999) == "99+")
    }
}
