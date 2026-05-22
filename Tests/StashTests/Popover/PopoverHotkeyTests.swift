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

    @Test("TASK-042 정정 — .copy 동적 조회 placeholder: keyCode == 0 / modifiers == [] (TASK-033 fix-2 PopoverShortcutStore 동적 조회 패턴 정합)")
    func copyKeyCodeAndModifiers() {
        // TASK-024 신설 시점: .copy hardcoded ⌘+C (keyCode=8 / modifiers=[.command]).
        // TASK-033 fix-2: 변경 가능 단축키 (.copy/.paste/.togglePin/.togglePinSidebar/.deleteOne/.deleteAll) 를 PopoverShortcutStore 동적 조회로 전환 — keyCode/modifiers 는 placeholder (0/[]) 반환, 실제 매칭은 store 가 담당.
        // 본 케이스는 *동적 조회 placeholder 회귀 가드* — hardcoded 로 되돌아가지 않도록.
        #expect(PopoverHotkey.copy.keyCode == 0)
        #expect(PopoverHotkey.copy.modifiers == [])
        #expect(PopoverHotkey.copy.popoverShortcutID == .copy)
    }

    // MARK: - TASK-051: .confirm Enter 분기 매칭

    @Test("TASK-051 — .confirm 매칭: 일반 Return (keyCode=36) 단독 true")
    func confirmMatchesPlainReturn() {
        let event = makeKeyEvent(keyCode: 36, modifiers: [])
        #expect(PopoverHotkey.confirm.matches(event: event) == true)
    }

    @Test("TASK-051 — .confirm 매칭: Numpad Enter (keyCode=76) 단독 true (일반 Return 과 동시 매칭)")
    func confirmMatchesNumpadEnter() {
        let event = makeKeyEvent(keyCode: 76, modifiers: [])
        #expect(PopoverHotkey.confirm.matches(event: event) == true)
    }

    @Test("TASK-051 — .confirm 비매칭: ⌘+Return false (modifier 조합 X)")
    func confirmDoesNotMatchCommandReturn() {
        let event = makeKeyEvent(keyCode: 36, modifiers: [.command])
        #expect(PopoverHotkey.confirm.matches(event: event) == false)
    }

    @Test("TASK-051 — .confirm 비매칭: ⇧+Return false (modifier 조합 X)")
    func confirmDoesNotMatchShiftReturn() {
        let event = makeKeyEvent(keyCode: 36, modifiers: [.shift])
        #expect(PopoverHotkey.confirm.matches(event: event) == false)
    }

    @Test("TASK-051 — .confirm 비매칭: Space (keyCode=49) 단독 false (다른 키)")
    func confirmDoesNotMatchSpace() {
        let event = makeKeyEvent(keyCode: 49, modifiers: [])
        #expect(PopoverHotkey.confirm.matches(event: event) == false)
    }

    @Test("TASK-051 — .confirm 정합: popoverShortcutID nil (변경 불가) / keyCode 36 primary / modifiers []")
    func confirmEnumProperties() {
        #expect(PopoverHotkey.confirm.popoverShortcutID == nil)
        #expect(PopoverHotkey.confirm.keyCode == 36)
        #expect(PopoverHotkey.confirm.modifiers == [])
    }

    @Test("TASK-051 — PopoverHotkey.allCases 에 .confirm 포함")
    func allCasesContainsConfirm() {
        #expect(PopoverHotkey.allCases.contains(.confirm))
    }

    @Test("TASK-055 — PopoverHotkey.allCases.count == 15 (TASK-051 14 case + TASK-055 .toggleClipDetail 신규)")
    func allCasesCountIsFifteen() {
        // TASK-025 시점 10 case → TASK-036 +4 → TASK-051 +1 (.confirm) → TASK-055 +1 (.toggleClipDetail).
        // 현재 enum 15 case: moveSelectionUp / moveSelectionDown / pageUp / pageDown / moveSelectionToFirst / moveSelectionToLast / togglePin / togglePinSidebar / deleteOne / deleteAll / copy / paste / confirm / escape / toggleClipDetail.
        #expect(PopoverHotkey.allCases.count == 15)
    }

    // MARK: - TASK-055: .toggleClipDetail (⌘+D) 매칭

    @Test("TASK-055 — .toggleClipDetail 매칭: ⌘+D (keyCode=2, command) 매치")
    func toggleClipDetailMatchesCommandD() {
        let event = makeKeyEvent(keyCode: 2, modifiers: [.command])
        #expect(PopoverHotkey.toggleClipDetail.matches(event: event) == true)
    }

    @Test("TASK-055 — .toggleClipDetail 비매칭: D 단독 (modifier 없음) — 검색바 텍스트 입력 시 d 키 정상 forward")
    func toggleClipDetailDoesNotMatchPlainD() {
        let event = makeKeyEvent(keyCode: 2, modifiers: [])
        #expect(PopoverHotkey.toggleClipDetail.matches(event: event) == false)
    }

    @Test("TASK-055 — .toggleClipDetail 비매칭: ⌘+⇧+D (다른 modifier 조합) false")
    func toggleClipDetailDoesNotMatchCommandShiftD() {
        let event = makeKeyEvent(keyCode: 2, modifiers: [.command, .shift])
        #expect(PopoverHotkey.toggleClipDetail.matches(event: event) == false)
    }

    @Test("TASK-055 — .toggleClipDetail 정합: popoverShortcutID nil (변경 불가) / keyCode 2 / modifiers [.command]")
    func toggleClipDetailEnumProperties() {
        #expect(PopoverHotkey.toggleClipDetail.popoverShortcutID == nil)
        #expect(PopoverHotkey.toggleClipDetail.keyCode == 2)
        #expect(PopoverHotkey.toggleClipDetail.modifiers == [.command])
    }

    // MARK: - TASK-025: 검색바 always-active 정책 회귀 가드

    @Test("TASK-025 — .escape matches: ESC 단독 true / ESC+⌘ false / ESC+⌥ false")
    func escapeMatching() {
        let plainEsc = makeKeyEvent(keyCode: 53, modifiers: [])
        let cmdEsc = makeKeyEvent(keyCode: 53, modifiers: [.command])
        let optEsc = makeKeyEvent(keyCode: 53, modifiers: [.option])
        #expect(PopoverHotkey.escape.matches(event: plainEsc) == true)
        #expect(PopoverHotkey.escape.matches(event: cmdEsc) == false)
        #expect(PopoverHotkey.escape.matches(event: optEsc) == false)
    }
}
