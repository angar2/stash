// PasteSynthesizer protocol 준수 — CGEvent ⌘V 합성으로 활성 앱에 붙여넣기 트리거
import AppKit
import CoreGraphics

struct CGEventPasteSynthesizer: PasteSynthesizer {
    // kVK_ANSI_V = 0x09
    private static let vKeyCode: CGKeyCode = 0x09

    func synthesizeCommandV() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else {
            throw PasteError.keyboardSimulationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
