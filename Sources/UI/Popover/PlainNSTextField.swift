// AppKit NSTextField를 SwiftUI에 wrap — SwiftUI .focused / @FocusState 우회 (TASK-016 D-3 fix)
// SwiftUI TextField + .focused는 NSPanel(.nonactivatingPanel) + KeyablePanel 환경에서 first responder 자동 처리가 불안정 (popover 열림 시 자동 first responder + makeFirstResponder(nil) 시 hover 부하). NSTextField는 자체 NSResponder chain으로 처리 → 명확한 동작.
import AppKit
import SwiftUI

struct PlainNSTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let placeholderAttributed: NSAttributedString?  // 박스 스타일 등 attributed placeholder. nil이면 placeholder String 사용.
    let font: NSFont
    let textColor: NSColor
    let onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> FocusTrackingTextField {
        let tf = FocusTrackingTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.backgroundColor = .clear
        tf.placeholderString = placeholder
        tf.font = font
        tf.textColor = textColor
        tf.focusRingType = .none
        tf.cell?.usesSingleLineMode = true
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.delegate = context.coordinator
        tf.target = context.coordinator
        tf.action = #selector(Coordinator.commit(_:))
        // becomeFirstResponder 시 onFocusChange(true) 호출 — controlTextDidBeginEditing보다 신뢰성 있음.
        tf.onBecomeFirstResponder = { onFocusChange(true) }
        return tf
    }

    func updateNSView(_ nsView: FocusTrackingTextField, context: Context) {
        // 편집 중에는 placeholder/font/textColor setter 호출 차단 — setter가 field editor reset → endEditing 즉시 발화하는 부작용 있음 (D-3 root cause).
        let isEditing = nsView.currentEditor() != nil

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        guard !isEditing else { return }

        if let attr = placeholderAttributed {
            if nsView.placeholderAttributedString != attr {
                nsView.placeholderAttributedString = attr
            }
        } else {
            // attributed → string 전환 시 attributed clear 필요
            if nsView.placeholderAttributedString != nil {
                nsView.placeholderAttributedString = nil
            }
            if nsView.placeholderString != placeholder {
                nsView.placeholderString = placeholder
            }
        }
        if nsView.font != font {
            nsView.font = font
        }
        if nsView.textColor != textColor {
            nsView.textColor = textColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PlainNSTextField
        init(_ parent: PlainNSTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocusChange(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onFocusChange(false)
        }

        @objc func commit(_ sender: Any?) {
            // Enter — 별도 처리 없음 (검색은 onChange로 실시간)
        }
    }
}

/// NSTextField subclass — becomeFirstResponder를 override해 정확한 focus 시점 잡음.
/// (NSTextFieldDelegate.controlTextDidBeginEditing은 텍스트 입력 시작 후 fire라 click 직후 시각 갱신에 부적합.)
final class FocusTrackingTextField: NSTextField {
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in
                // dispatch 시점에 *실제로* self가 first responder인지 검증.
                // panel.makeKey의 자동 first responder set → becomeFirstResponder=true → 그 후 makeFirstResponder(panel)로 잃었어도 dispatch는 등록된 채 fire.
                // 검증 없이 호출하면 popover 열림 시 active=true 잘못 set (D-3 잔존 root cause).
                guard let self, let win = self.window else { return }
                let isStillFocused = (win.firstResponder === self) || (win.firstResponder === self.currentEditor())
                if isStillFocused {
                    self.onBecomeFirstResponder?()
                }
            }
        }
        return result
    }
}
