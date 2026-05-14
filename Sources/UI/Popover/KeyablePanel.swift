// borderless NSPanel이 key window가 되어 SwiftUI .onKeyPress / TextField first responder 처리 가능하게 (canBecomeKey override)
import AppKit

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
