// KeyablePanel.resolveResizeHeight — autoFit ON/OFF 분기 단위 테스트 (TASK-063)
// autoFit ON 시 사용자 height 드래그 시도 무시 (popover 미추종) + width 드래그 wrap 추종 fitting 우선.
// autoFit OFF 시 시스템 제안 그대로 통과 (기존 TASK-054 height 1행 snap 흐름 진입).
import Testing
import CoreGraphics
@testable import stash

@MainActor
@Suite("KeyablePanel.resolveResizeHeight (TASK-063 autoFit drag block)")
struct PopoverResizeAutoFitTests {

    @Test("TASK-063 — autoFit OFF: proposedHeight 그대로 통과 (시스템 제안 → 기존 snap 흐름)")
    func autoFitOff_proposedPassesThrough() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: false,
            proposedHeight: 500,
            currentHeight: 300,
            measuredFittingHeight: 320
        )
        #expect(result == 500, "autoFit OFF — 시스템 제안 height 그대로 반환 (measuredFittingHeight 무시)")
    }

    @Test("TASK-063 — autoFit ON + measured 존재: width drag wrap 추종 fitting 우선")
    func autoFitOn_widthDragUsesFitting() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 500,
            currentHeight: 300,
            measuredFittingHeight: 320
        )
        #expect(result == 320, "autoFit ON — measuredFittingHeight 우선 (width 드래그로 hintBar wrap 줄 변동 시 자동 추종)")
    }

    @Test("TASK-063 — autoFit ON + measured nil: currentHeight fallback (안전망)")
    func autoFitOn_measuredNilFallsBackToCurrent() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 500,
            currentHeight: 300,
            measuredFittingHeight: nil
        )
        #expect(result == 300, "autoFit ON + currentHosting 미주입 — 현재 height 박아 popover 미추종 유지")
    }

    @Test("TASK-063 — autoFit ON + 축소 시도: fitting 우선 (사용자 끌어당김 무관 측정값 박음)")
    func autoFitOn_shrinkAttemptAlsoUsesFitting() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 300,
            currentHeight: 500,
            measuredFittingHeight: 480
        )
        #expect(result == 480, "autoFit ON — 축소/확대 방향 무관 measuredFittingHeight 우선 (autoFit 정책 = 자동 계산값 진실)")
    }
}
