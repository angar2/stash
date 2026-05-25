// KeyablePanel.resolveResizeHeight — autoFit ON/OFF cap clamp 단위 테스트 (TASK-077, TASK-063 회귀 fix)
// 사용자 요구: popover 사이즈 변경은 언제나 가능. autoFit ON + 클립 수 추적 높이 초과 시도만 차단.
// autoFit OFF — proposedHeight 그대로 통과.
// autoFit ON + measured 있음 — min(proposedHeight, measured) 반환.
// autoFit ON + measured nil — proposedHeight 그대로 (안전망).
import Testing
import CoreGraphics
@testable import stash

@MainActor
@Suite("KeyablePanel.resolveResizeHeight (TASK-077 autoFit cap clamp)")
struct PopoverResizeAutoFitTests {

    @Test("TASK-077 — autoFit OFF: proposedHeight 그대로 통과")
    func autoFitOff_proposedPassesThrough() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: false,
            proposedHeight: 500,
            measuredFittingHeight: 320
        )
        #expect(result == 500, "autoFit OFF — measured 무시, 시스템 제안 그대로")
    }

    @Test("TASK-077 — autoFit ON + cap 이하: proposedHeight 자유 통과 (축소)")
    func autoFitOn_belowCap_passes() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 300,
            measuredFittingHeight: 480
        )
        #expect(result == 300, "autoFit ON + proposedHeight ≤ cap — 자유 통과")
    }

    @Test("TASK-077 — autoFit ON + cap 초과: cap 차단")
    func autoFitOn_aboveCap_clamped() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 500,
            measuredFittingHeight: 320
        )
        #expect(result == 320, "autoFit ON + proposedHeight > cap — cap 에서 멈춤")
    }

    @Test("TASK-077 — autoFit ON + cap 동일: 그대로 통과")
    func autoFitOn_equalCap_passes() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 400,
            measuredFittingHeight: 400
        )
        #expect(result == 400, "autoFit ON + proposedHeight == cap — min 자연 통과")
    }

    @Test("TASK-077 — autoFit ON + measured nil: proposedHeight 자유 통과 (안전망)")
    func autoFitOn_measuredNil_passes() {
        let result = KeyablePanel.resolveResizeHeight(
            autoFit: true,
            proposedHeight: 500,
            measuredFittingHeight: nil
        )
        #expect(result == 500, "autoFit ON + measured nil — cap 측정 불가, 자유 통과 (안전망)")
    }

    @Test("TASK-077 — computeAutoFitCap: visibleCount > clipsPerPage → 추가 행 분량 더해 cap 산출")
    func computeAutoFitCap_visibleGreaterThanClipsPerPage() {
        // measured = 6행 fitting (clipsPerPage 기반), visibleCount=10, capRows=15 → 추가 4행 더해 cap.
        let cap = ClipsViewModel.computeAutoFitCap(
            measured: 426,
            visibleCount: 10,
            clipsPerPage: 6,
            capRows: 15,
            rowHeight: 38,
            rowGap: 8
        )
        #expect(cap == 610.0, "visibleCount 10 > clipsPerPage 6 — 추가 4행 (10-6) * snap(46) = 184 더함 (426+184=610)")
    }

    @Test("TASK-077 — computeAutoFitCap: visibleCount ≤ clipsPerPage → cap = measured (추가 X)")
    func computeAutoFitCap_visibleLessOrEqualClipsPerPage() {
        let cap = ClipsViewModel.computeAutoFitCap(
            measured: 288,
            visibleCount: 3,
            clipsPerPage: 6,
            capRows: 15,
            rowHeight: 38,
            rowGap: 8
        )
        #expect(cap == 288, "visibleCount 3 ≤ clipsPerPage 6 — 추가 행 0, cap = measured")
    }

    @Test("TASK-077 — computeAutoFitCap: capRows < visibleCount → 화면 cap 까지만 추가")
    func computeAutoFitCap_capRowsLessThanVisible() {
        // visibleCount=20, clipsPerPage=6, capRows=10 → targetRows = min(20, 10) = 10. extraRows = 10-6 = 4.
        let cap = ClipsViewModel.computeAutoFitCap(
            measured: 426,
            visibleCount: 20,
            clipsPerPage: 6,
            capRows: 10,
            rowHeight: 38,
            rowGap: 8
        )
        #expect(cap == 610.0, "capRows 10 < visibleCount 20 — targetRows = capRows = 10, extraRows = 4, cap = 426+4*46 = 610")
    }
}
