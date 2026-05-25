// TASK-083 — PopoverShortcutRecorder focus-out 판정 헬퍼 (isFocusOutClick) 단위 검증
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverShortcutRecorder focus-out (TASK-083)")
struct PopoverShortcutRecorderFocusOutTests {

    /// 헬퍼 — 임시 NSWindow 1개 생성. AppKit 인스턴스화 자체 — NSApp 의존 X.
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    @Test("같은 윈도우 + Recorder bounds 안 클릭 → focus-out 아님")
    func insideClick_sameWindow_returnsFalse() {
        let window = makeWindow()
        let recorderBounds = CGRect(x: 100, y: 100, width: 100, height: 22)
        let pointInside = CGPoint(x: 150, y: 110) // bounds 정중앙 부근
        let isOut = PopoverShortcutRecorderViewCocoa.isFocusOutClick(
            eventLocationInWindow: pointInside,
            eventWindow: window,
            recorderWindow: window,
            recorderBoundsInWindow: recorderBounds
        )
        #expect(isOut == false, "Recorder bounds 안 클릭은 focus-out trigger X")
    }

    @Test("같은 윈도우 + Recorder bounds 밖 클릭 → focus-out trigger")
    func outsideClick_sameWindow_returnsTrue() {
        let window = makeWindow()
        let recorderBounds = CGRect(x: 100, y: 100, width: 100, height: 22)
        let pointOutside = CGPoint(x: 50, y: 50) // bounds 좌하단 바깥
        let isOut = PopoverShortcutRecorderViewCocoa.isFocusOutClick(
            eventLocationInWindow: pointOutside,
            eventWindow: window,
            recorderWindow: window,
            recorderBoundsInWindow: recorderBounds
        )
        #expect(isOut == true, "Recorder bounds 밖 클릭은 focus-out trigger O")
    }

    @Test("다른 윈도우 이벤트 → focus-out 아님 (didResignKey 가 별도 처리)")
    func otherWindowEvent_returnsFalse() {
        let recorderWindow = makeWindow()
        let otherWindow = makeWindow()
        let recorderBounds = CGRect(x: 100, y: 100, width: 100, height: 22)
        let point = CGPoint(x: 50, y: 50) // bounds 밖 좌표
        let isOut = PopoverShortcutRecorderViewCocoa.isFocusOutClick(
            eventLocationInWindow: point,
            eventWindow: otherWindow,
            recorderWindow: recorderWindow,
            recorderBoundsInWindow: recorderBounds
        )
        #expect(isOut == false, "다른 윈도우 이벤트는 무관 (localMonitor 가 잡지 못하는 경로 — didResignKey 가 처리)")
    }

    @Test("eventWindow nil → focus-out 아님")
    func nilEventWindow_returnsFalse() {
        let recorderWindow = makeWindow()
        let recorderBounds = CGRect(x: 100, y: 100, width: 100, height: 22)
        let isOut = PopoverShortcutRecorderViewCocoa.isFocusOutClick(
            eventLocationInWindow: CGPoint(x: 50, y: 50),
            eventWindow: nil,
            recorderWindow: recorderWindow,
            recorderBoundsInWindow: recorderBounds
        )
        #expect(isOut == false, "eventWindow nil 시 안전 fallback")
    }

    @Test("recorderWindow nil → focus-out 아님 (view 가 윈도우 박히지 않은 상태)")
    func nilRecorderWindow_returnsFalse() {
        let eventWindow = makeWindow()
        let recorderBounds = CGRect(x: 100, y: 100, width: 100, height: 22)
        let isOut = PopoverShortcutRecorderViewCocoa.isFocusOutClick(
            eventLocationInWindow: CGPoint(x: 50, y: 50),
            eventWindow: eventWindow,
            recorderWindow: nil,
            recorderBoundsInWindow: recorderBounds
        )
        #expect(isOut == false, "recorderWindow nil 시 안전 fallback (view 가 윈도우 박히지 않은 상태)")
    }

    @Test("bounds 경계 좌표 — top-left 코너는 안쪽 포함 (CGRect.contains 룰)")
    func boundsCorner_isInside() {
        let window = makeWindow()
        let recorderBounds = CGRect(x: 100, y: 100, width: 100, height: 22)
        // CGRect.contains: minX/minY 포함, maxX/maxY 미포함
        let cornerInside = CGPoint(x: 100, y: 100)
        let isOut = PopoverShortcutRecorderViewCocoa.isFocusOutClick(
            eventLocationInWindow: cornerInside,
            eventWindow: window,
            recorderWindow: window,
            recorderBoundsInWindow: recorderBounds
        )
        #expect(isOut == false, "bounds.origin 좌표는 contains true → focus-out X")
    }
}
