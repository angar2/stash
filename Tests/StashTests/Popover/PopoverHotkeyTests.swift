// PopoverHotkey enum 단위 테스트 — keyCode + modifier 매칭 (TASK-024 ⌘+C 신규 + ⌘+V 권한 게이트 영향 검증)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverHotkey")
struct PopoverHotkeyTests {
    /// NSEvent.keyEvent 정적 생성자 — keyCode + modifier 조합으로 합성 event 생성.
    private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("NSEvent.keyEvent 생성 실패")
        }
        return event
    }

    // MARK: - TASK-024: .copy 매칭

    @Test("TASK-024 — .copy 매칭: ⌘+C (keyCode=8, command) 매치")
    func copyMatchesCommandC() {
        let event = makeKeyEvent(keyCode: 8, modifiers: [.command])
        #expect(PopoverHotkey.copy.matches(event: event) == true)
    }

    @Test("TASK-024 — .copy 비매칭: C 단독 (modifier 없음) 매치 X")
    func copyDoesNotMatchPlainC() {
        let event = makeKeyEvent(keyCode: 8, modifiers: [])
        #expect(PopoverHotkey.copy.matches(event: event) == false)
    }

    @Test("TASK-024 — .copy 비매칭: ⌘+⇧+C (다른 modifier 조합) 매치 X")
    func copyDoesNotMatchCommandShiftC() {
        let event = makeKeyEvent(keyCode: 8, modifiers: [.command, .shift])
        #expect(PopoverHotkey.copy.matches(event: event) == false)
    }

    @Test("TASK-024 — .copy 비매칭: ⌘+V (다른 키) 매치 X")
    func copyDoesNotMatchCommandV() {
        let event = makeKeyEvent(keyCode: 9, modifiers: [.command])
        #expect(PopoverHotkey.copy.matches(event: event) == false)
    }

    // MARK: - .paste 매칭 (TASK-024 권한 게이트와 무관 — enum 매칭은 권한 검사 안 함)

    @Test(".paste 매칭: ⌘+V (keyCode=9, command) 매치")
    func pasteMatchesCommandV() {
        let event = makeKeyEvent(keyCode: 9, modifiers: [.command])
        #expect(PopoverHotkey.paste.matches(event: event) == true)
    }

    @Test(".paste 비매칭: V 단독 매치 X")
    func pasteDoesNotMatchPlainV() {
        let event = makeKeyEvent(keyCode: 9, modifiers: [])
        #expect(PopoverHotkey.paste.matches(event: event) == false)
    }

    // MARK: - allCases 포함 검증 (TASK-024 — .copy enum 등록 보증)

    @Test("TASK-024 — PopoverHotkey.allCases 에 .copy 포함")
    func allCasesContainsCopy() {
        #expect(PopoverHotkey.allCases.contains(.copy))
    }

    @Test("TASK-024 — .copy.keyCode == 8 / .copy.modifiers == [.command]")
    func copyKeyCodeAndModifiers() {
        #expect(PopoverHotkey.copy.keyCode == 8)
        #expect(PopoverHotkey.copy.modifiers == [.command])
    }
}
