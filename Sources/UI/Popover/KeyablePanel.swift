// borderless NSPanel이 key window가 되어 SwiftUI .onKeyPress / TextField first responder 처리 가능하게 (canBecomeKey override)
// TASK-017: SwiftUI .onKeyPress가 NSPanel(.nonactivatingPanel) 환경에서 발화 안 함 — focused View가 responder chain에 없음.
// keyDown override + keyDownHandler closure inject로 AppKit 단에서 직접 키 이벤트 가로채 ViewModel 액션 호출.
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
}
