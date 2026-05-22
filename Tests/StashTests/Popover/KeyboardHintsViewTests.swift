// KeyboardHintsView.hints 배열 구조 검증 — TASK-050 이동 단축키 3 hint → 1 통합 cell + pin 순서 재배치
// 단축키 라우팅 변경 X — 시각 표현만. PopoverShortcutStore 미주입 시 fallback 키 표시 검증.
@testable import stash
import Testing

@Suite("KeyboardHintsView — hints 배열 구조 (TASK-050)")
struct KeyboardHintsViewTests {

    @Test("hints.count == 6 — move 통합 후 6 개 cell (move / copy / paste / pin / del / delAll)")
    func hintsCount() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        #expect(view.hints.count == 6)
    }

    @Test("hints id 순서 — pin 이 del 앞으로 재배치")
    func hintsOrder() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let ids = view.hints.map { $0.id }
        #expect(ids == ["move", "copy", "paste", "pin", "del", "delAll"])
    }

    @Test("move hint — parts.count == 3 (keys 3 그룹 연속, separator 없음)")
    func moveHintPartsCount() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let moveHint = view.hints[0]
        #expect(moveHint.id == "move")
        #expect(moveHint.parts.count == 3)
    }

    @Test("move hint — keys 배열 [↑↓] / [⌘↑↓] / [⌘⇧↑↓] (키캡 안 화살표 2 문자 동시)")
    func moveHintKeys() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let moveHint = view.hints[0]
        var keysByPart: [[String]] = []
        for part in moveHint.parts {
            if case .keys(let arr) = part {
                keysByPart.append(arr)
            }
        }
        #expect(keysByPart == [["↑↓"], ["⌘↑↓"], ["⌘⇧↑↓"]])
    }

    @Test("paste hint — Accessibility 권한 X 시 enabled=false (TASK-024 회귀 검증)")
    func pasteHintAccessibilityGate() {
        let granted = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let revoked = KeyboardHintsView(mode: .method1, accessibilityGranted: false)
        let pasteGranted = granted.hints.first { $0.id == "paste" }
        let pasteRevoked = revoked.hints.first { $0.id == "paste" }
        #expect(pasteGranted?.enabled == true)
        #expect(pasteRevoked?.enabled == false)
    }

    @Test("move / copy / pin / del / delAll — enabled=true (Accessibility 권한 무관)")
    func nonPasteHintsAlwaysEnabled() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: false)
        for id in ["move", "copy", "pin", "del", "delAll"] {
            let hint = view.hints.first { $0.id == id }
            #expect(hint?.enabled == true, "\(id) hint enabled 기대 true")
        }
    }
}
