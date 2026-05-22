// KeyablePanel.computeSnapDelta — 1행 snap + cap clamp 단위 테스트 (TASK-054)
// NSEvent.deltaY 컨벤션: 마우스 아래로 양수 / 위로 음수 (Apple 표준).
// 직관: 테두리 잡고 *끌어당기는 방향* = height 증가 (NSWindow 표준 리사이즈 정합).
import Testing
import CoreGraphics
@testable import stash

@MainActor
@Suite("KeyablePanel.computeSnapDelta (TASK-054 edge resize)")
struct PopoverResizeTests {

    private let snap: CGFloat = 46  // rowMinHeight (44) + rowGap (2)

    @Test("TASK-054 — dragDy 0 → delta 0 + residual 0")
    func noDrag() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: 0, isTop: true, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == 0)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — top edge, accumulated -46 (마우스 위로 끌어당김) → delta +1 (height 증가)")
    func topEdgeOneSnapIncrease() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -46, isTop: true, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == 1)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — top edge, accumulated -92 (마우스 위로 92pt) → delta +2 + residual 0")
    func topEdgeTwoSnaps() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -92, isTop: true, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == 2)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — accumulated -45 → snap 미달 (delta 0 + residual -45 보존)")
    func belowSnapThreshold() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -45, isTop: true, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == 0)
        #expect(r.residualDy == -45)
    }

    @Test("TASK-054 — top edge, accumulated -50 → 1 snap + residual -4pt 보존")
    func partialSnapResidual() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -50, isTop: true, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == 1)
        #expect(r.residualDy == -4)
    }

    @Test("TASK-054 — top edge, accumulated +46 (마우스 아래로) → delta -1 (height 감소)")
    func topEdgeOneSnapDecrease() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: 46, isTop: true, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == -1)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — bottom edge, accumulated +46 (마우스 아래로 끌어당김) → delta +1 (height 증가)")
    func bottomEdgeOneSnapIncrease() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: 46, isTop: false, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == 1)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — bottom edge, accumulated -46 (마우스 위로) → delta -1 (height 감소)")
    func bottomEdgeOneSnapDecrease() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -46, isTop: false, snap: snap, current: 6, min: 1, max: 50)
        #expect(r.delta == -1)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — cap 도달 (current=max=50, top edge -46 위로) → delta 0 + residual reset")
    func capUpperReached() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -46, isTop: true, snap: snap, current: 50, min: 1, max: 50)
        #expect(r.delta == 0)
        #expect(r.residualDy == 0, "cap 도달 시 누적 reset (반대 방향 즉시 반응)")
    }

    @Test("TASK-054 — cap 도달 (current=min=1, top edge +46 아래로) → delta 0 + residual reset")
    func capLowerReached() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: 46, isTop: true, snap: snap, current: 1, min: 1, max: 50)
        #expect(r.delta == 0)
        #expect(r.residualDy == 0)
    }

    @Test("TASK-054 — cap 직전 (current=49, top edge -92 위로) → effective delta = 1 (cap 까지만)")
    func capPartialClamp() {
        let r = KeyablePanel.computeSnapDelta(accumulatedDy: -92, isTop: true, snap: snap, current: 49, min: 1, max: 50)
        #expect(r.delta == 1, "49 → 50 max — 2 step 요청이지만 1 만 적용")
    }
}
