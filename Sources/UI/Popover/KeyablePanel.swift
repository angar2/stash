// borderless NSPanel이 key window가 되어 SwiftUI .onKeyPress / TextField first responder 처리 가능하게 (canBecomeKey override)
// TASK-017: SwiftUI .onKeyPress가 NSPanel(.nonactivatingPanel) 환경에서 발화 안 함 — focused View가 responder chain에 없음.
// keyDown override + keyDownHandler closure inject로 AppKit 단에서 직접 키 이벤트 가로채 ViewModel 액션 호출.
// TASK-054 fix-1: 수동 mouseDown/Dragged/Moved/Up override + edge state + edgeHitZone 헬퍼 모두 폐기 — macOS 시스템 표준 `NSWindow.styleMask.resizable` 위임.
// 본 클래스는 NSPanel + keyDownHandler + constrainFrameRect override + `computeSnapDelta` 정적 헬퍼 (테스트 진입점) 만 남음.
import AppKit

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Window가 inject — keyDown event를 받아 처리하면 true 반환. nil이거나 false 반환 시 super 호출 (SwiftUI HostingView로 forward).
    var keyDownHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if let handler = keyDownHandler, handler(event) {
            return  // handled — super 호출 차단
        }
        super.keyDown(with: event)
    }

    /// TASK-037 fix-5 — macOS 자동 frame 보정 차단. setFrame / setFrameOrigin 호출 시 우리가 박은 frame 그대로 사용.
    /// 사유: visible 영역 초과 시 macOS 가 popover 위치를 자동 보정 (visible 안으로 이동). 우하단 anchor 정합 깨짐.
    /// 호출처 (refreshFrame / positionAtAnchor) 가 화면 cap + 좌표 정확성 책임.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    /// TASK-054 — edge resize 1행 snap 순수 함수 (NSEvent 의존 X — 단위 테스트 진입점).
    /// TASK-054 fix-1 — 본 헬퍼는 `PopoverWindow.windowWillResize(_:to:)` 안에서 호출. NSWindow 가 시스템 resize 흐름으로 전달한 *제안 size* 와 *기존 frame* 의 dy 를 받아 snap 정수 차이 + 잔여 dy 반환.
    /// 방향 결정: 시스템 windowWillResize 가 전달하는 size 는 시스템 표준 — *마우스 끌어당기는 방향 = size 증가* (NSWindow 표준 직관, accumulated dy = 시스템 자동 컨벤션).
    /// 본 함수는 input/output 계약 그대로 유지 — accumulated dy < 0 = height 증가 방향 (상단 끌어 위로), > 0 = 감소.
    /// 단 시스템 resize 컨벤션상 *delta size 의 부호* 로 변환해 호출 시 정합.
    /// cap (`min`/`max`) 도달 시 effective delta 0 + 누적 dy reset (반대 방향 즉시 반응).
    /// - Returns: (delta: clipsPerPage 변경 요청 정수, residualDy: 잔여 누적 dy)
    static func computeSnapDelta(
        accumulatedDy: CGFloat,
        isTop: Bool,
        snap: CGFloat,
        current: Int,
        min minValue: Int,
        max maxValue: Int
    ) -> (delta: Int, residualDy: CGFloat) {
        let absDy = abs(accumulatedDy)
        guard absDy >= snap else { return (0, accumulatedDy) }
        let steps = Int(absDy / snap)
        let direction: Int
        if isTop {
            // 상단 잡고 위로 (deltaY 음수) = 끌어당김 → +1
            direction = accumulatedDy < 0 ? 1 : -1
        } else {
            // 하단 잡고 아래로 (deltaY 양수) = 끌어당김 → +1
            direction = accumulatedDy > 0 ? 1 : -1
        }
        let delta = direction * steps
        var effective = delta
        if effective > 0 && current + effective > maxValue {
            effective = maxValue - current
        }
        if effective < 0 && current + effective < minValue {
            effective = minValue - current
        }
        if effective == 0 {
            // cap 도달 → 누적 dy reset (반대 방향 즉시 반응).
            return (0, 0)
        }
        // 잔여 dy = 누적 dy 부호 기준 consumed 만큼 차감 (direction 부호 X — bottom edge 케이스에서 accumulated 와 delta 부호 반대 가능).
        let absSign: CGFloat = accumulatedDy >= 0 ? 1 : -1
        let residual = accumulatedDy - absSign * CGFloat(steps) * snap
        return (effective, residual)
    }
}
