// PopoverWindow.computePinSidebarHeight — 핀 사이드바 동적 height 계산 단위 테스트 (TASK-048 회귀 가드)
import Testing
import CoreGraphics
@testable import stash

@MainActor
@Suite("PopoverWindow.computePinSidebarHeight (TASK-048)")
struct PinSidebarHeightTests {
    /// 1 pin — gap 0 개. clamp 진입 X. header + 1 row + outerPad 동치.
    @Test("TASK-048 — 1 pin 결과 = header + rowMinHeight + outerPad")
    func singlePin() {
        let expected = DesignTokens.Spacing.pinSidebarHeaderHeight
            + DesignTokens.Spacing.rowMinHeight
            + DesignTokens.Spacing.pinSidebarPadding * 2
        let result = PopoverWindow.computePinSidebarHeight(pinnedCount: 1)
        #expect(result == expected, "1 pin 의 결과가 식과 동치여야 함 (expected=\(expected), got=\(result))")
    }

    /// 5 pins — gap 4 개. 중간 케이스, LazyVStack(spacing:) 의 (count-1) gaps 정합 검증.
    @Test("TASK-048 — 5 pins 결과 = header + 5*rowMinHeight + 4*rowGap + outerPad")
    func fivePinsGapsMatchLazyVStack() {
        let expected = DesignTokens.Spacing.pinSidebarHeaderHeight
            + 5 * DesignTokens.Spacing.rowMinHeight
            + 4 * DesignTokens.Spacing.rowGap
            + DesignTokens.Spacing.pinSidebarPadding * 2
        let result = PopoverWindow.computePinSidebarHeight(pinnedCount: 5)
        #expect(result == expected, "5 pins 의 결과가 (count-1) gaps 식과 동치여야 함 (expected=\(expected), got=\(result))")
    }

    /// 10 pins — maxPinnedClips 하드 캡 경계. clamp 진입 X 가 핵심 (마지막 행 잘림 회귀 가드).
    @Test("TASK-048 — 10 pins 가 popoverHeight - bottomMargin 이내 fit (clamp 진입 X)")
    func tenPinsFitsWithoutClamp() {
        let upperBound = DesignTokens.WindowSize.popoverHeight - DesignTokens.Spacing.pinSidebarHeightBottomMargin
        let rawContentH = DesignTokens.Spacing.pinSidebarHeaderHeight
            + 10 * DesignTokens.Spacing.rowMinHeight
            + 9 * DesignTokens.Spacing.rowGap
            + DesignTokens.Spacing.pinSidebarPadding * 2
        let result = PopoverWindow.computePinSidebarHeight(pinnedCount: 10)
        #expect(rawContentH <= upperBound, "10 pins raw content height (\(rawContentH)) 가 upperBound (\(upperBound)) 이내여야 함 — 회귀 시 마지막 행 잘림 재발")
        #expect(result == rawContentH, "10 pins 결과가 clamp 없이 raw content height 와 동치여야 함 (expected=\(rawContentH), got=\(result))")
    }

    /// 0 pin — max(1, count) 가드. 1 pin 결과와 동치 (헤더만 보여줄 때도 1 row 슬롯 확보).
    @Test("TASK-048 — 0 pin 결과가 1 pin 결과와 동치 (max(1, count) 가드)")
    func zeroPinFallsBackToOne() {
        let one = PopoverWindow.computePinSidebarHeight(pinnedCount: 1)
        let zero = PopoverWindow.computePinSidebarHeight(pinnedCount: 0)
        #expect(zero == one, "0 pin 가 max(1, count) 가드로 1 pin 결과와 동치여야 함 (one=\(one), zero=\(zero))")
    }
}
