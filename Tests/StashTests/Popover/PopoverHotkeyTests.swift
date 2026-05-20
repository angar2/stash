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

    // MARK: - TASK-025: 검색바 always-active 정책 회귀 가드

    @Test("TASK-025 — .activateSearch enum 제거 가드: Enter (keyCode=36) 단독 매칭 0건")
    func enterKeyMatchesNoHotkey() {
        let event = makeKeyEvent(keyCode: 36, modifiers: [])
        let matched = PopoverHotkey.allCases.contains { $0.matches(event: event) }
        #expect(matched == false)
    }

    @Test("TASK-042 정정 — PopoverHotkey.allCases.count == 13 (TASK-036 페이지/양끝 점프 4 case 합산 후 정합)")
    func allCasesCountIsThirteen() {
        // TASK-025 신설 시점: Enter 폐기 후 10 case.
        // TASK-036 추가: pageUp / pageDown / moveSelectionToFirst / moveSelectionToLast 4 case → 14 가 아닌 13 인 이유는 TASK-024 ⌘+C/.copy 도입 시 +1 / TASK-021 cursor 숫자 alias 2 case 폐기 / TASK-025 .activateSearch 1 case 폐기 종합 결과.
        // 현재 enum: moveSelectionUp / moveSelectionDown / pageUp / pageDown / moveSelectionToFirst / moveSelectionToLast / togglePin / togglePinSidebar / deleteOne / deleteAll / copy / paste / escape — 13 case.
        #expect(PopoverHotkey.allCases.count == 13)
    }

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
