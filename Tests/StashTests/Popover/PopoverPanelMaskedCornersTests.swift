// PopoverPanel.make() — popover 4 모서리 둥글기 회귀 차단 단위 테스트 (TASK-038, TASK-037 fix-11 회귀 방지)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverPanel maskedCorners (TASK-038)")
struct PopoverPanelMaskedCornersTests {
    /// TASK-038 — `make()` 가 반환한 `NSVisualEffectView.layer` 가 사방 4 모서리 모두 마스킹(둥글기) 적용 검증.
    /// TASK-037 fix-11 에서 `maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]` 로 상단 2 모서리만 박아 하단이 직각으로 렌더링되던 회귀 차단.
    @Test("TASK-038 — make() 결과는 4 모서리 모두 cornerRadius 적용")
    func makeAppliesAllFourCorners() {
        let (_, ve) = PopoverPanel.make(width: 380, height: 480)

        let mask = ve.layer?.maskedCorners
        let expected: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ]
        #expect(mask == expected, "popover layer 는 사방 4 모서리 모두 마스킹되어야 함 (CACornerMask default)")

        #expect(ve.layer?.cornerRadius == DesignTokens.Radius.popoverOuter, "cornerRadius 는 DesignTokens.Radius.popoverOuter (18) 와 일치해야 함")
        #expect(ve.layer?.masksToBounds == true, "masksToBounds 는 true 여야 cornerRadius 가 시각 적용됨")
    }
}
