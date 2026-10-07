// PopoverHotkey enum 단축키 매핑 검증 (TASK-017 리팩토링 회귀 방지). TASK-116 — HotkeyMonitorTests.swift 를 지우며 이 파일로 옮겼다.
import Testing
import Foundation
import AppKit
@testable import stash

// TASK-042 — PopoverHotkeyTests (`Tests/StashTests/Popover/PopoverHotkeyTests.swift`, TASK-024) 와 이름 충돌 회피 위해 `PopoverHotkeyMappingTests` 로 리네임.

@MainActor
@Suite("PopoverHotkey — mapping")
struct PopoverHotkeyMappingTests {
    /// keyCode + modifiers 매핑이 FEATURES §4 사양과 일치하는지 검증.
    @Test("↑ 단독 keyCode=126 modifiers=[] (TASK-021)")
    func upArrow_matchesPlainUp() {
        #expect(PopoverHotkey.moveSelectionUp.keyCode == 126)
        #expect(PopoverHotkey.moveSelectionUp.modifiers == [])
    }

    @Test("↓ 단독 keyCode=125 modifiers=[] (TASK-021)")
    func downArrow_matchesPlainDown() {
        #expect(PopoverHotkey.moveSelectionDown.keyCode == 125)
        #expect(PopoverHotkey.moveSelectionDown.modifiers == [])
    }

    @Test("⌘+↑ pageUp keyCode=126 modifiers=[.command] (TASK-036 페이지 점프)")
    func pageUp_matchesCommandUp() {
        #expect(PopoverHotkey.pageUp.keyCode == 126)
        #expect(PopoverHotkey.pageUp.modifiers == [.command])
    }

    @Test("⌘+↓ pageDown keyCode=125 modifiers=[.command] (TASK-036 페이지 점프)")
    func pageDown_matchesCommandDown() {
        #expect(PopoverHotkey.pageDown.keyCode == 125)
        #expect(PopoverHotkey.pageDown.modifiers == [.command])
    }

    @Test("⌘+⇧+↑ moveSelectionToFirst keyCode=126 modifiers=[.command,.shift] (TASK-036 Home)")
    func moveSelectionToFirst_matchesCommandShiftUp() {
        #expect(PopoverHotkey.moveSelectionToFirst.keyCode == 126)
        #expect(PopoverHotkey.moveSelectionToFirst.modifiers == [.command, .shift])
    }

    @Test("⌘+⇧+↓ moveSelectionToLast keyCode=125 modifiers=[.command,.shift] (TASK-036 End)")
    func moveSelectionToLast_matchesCommandShiftDown() {
        #expect(PopoverHotkey.moveSelectionToLast.keyCode == 125)
        #expect(PopoverHotkey.moveSelectionToLast.modifiers == [.command, .shift])
    }

    // TASK-020 — pop (⌘⇧V) 단축키 폐기로 pop_matchesCommandShiftV 케이스 삭제.
    // TASK-021 — moveSelectionUpAlias / moveSelectionDownAlias (⌘+1 / ⌘+2) enum 폐기로 alias 검증 케이스 삭제.

    // TASK-033 — deleteAll keyCode/modifiers hardcoded 검증 폐기 (변경 가능 단축키 → SPM 동적 조회로 변경. hardcoded 모두 keyCode=0, modifiers=[]). 변경 가능 단축키 검증은 SPM 등록값 기반 신규 테스트로 분리.

    // TASK-025 — `.activateSearch` enum case 폐기. Enter 동작 자체 제거 (검색바 always-active 정책). `activateSearch_matchesPlainReturn` 케이스 삭제. 회귀 가드는 `PopoverHotkeyTests` 의 `enterKeyMatchesNoHotkey` (Enter 단독 매칭 0건 검증) 에서 담당.

    @Test("ESC 단독 keyCode=53 modifiers=[] (예외)")
    func escape_matchesPlainEscape() {
        #expect(PopoverHotkey.escape.keyCode == 53)
        #expect(PopoverHotkey.escape.modifiers == [])
    }

    /// 방향키 키 자동 .numericPad/.function modifier가 매칭에 영향 X 검증 (TASK-017 fix-2 회귀 방지, TASK-021 정합).
    @Test("matches — 방향키 .numericPad+.function modifier 자동 박혀도 ↑ 단독 매칭 OK")
    func matches_ignoresNumericPadAndFunctionModifiers() {
        // ↑ event 시뮬레이션 — modifierFlags에 .numericPad + .function 박힘 (modifier-less 방향키)
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.numericPad, .function],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        #expect(PopoverHotkey.moveSelectionUp.matches(event: event) == true)
    }

    // TASK-033 — *modifier 정확 일치 검증* / *allCases 중복 keyCode+modifiers 없음* 테스트 폐기.
    // 사유: 변경 가능 단축키 6종 (copy / paste / pinToggle / pinSidebarToggle / deleteOne / deleteAll) 은 KeyboardShortcuts SPM 등록값 동적 조회로 변경. hardcoded keyCode + modifiers 기반 검증 의미 잃음 (모두 keyCode=0, modifiers=[]). deleteAllAlias 케이스 자체 폐기 (TASK-021 단축키 ⌘⇧⌫ 폐기 잔존 정리).
    // 변경 가능 단축키 검증은 KeyboardShortcuts SPM 동적 등록값 기반 신규 테스트로 분리 가능 (별도 후속 작업).

    /// allCases — 변경 불가 단축키 (방향키/ESC/⌘+방향키/⌘+⇧+방향키) keyCode+modifiers hardcoded 중복 없음.
    @Test("allCases — 변경 불가 단축키만 keyCode+modifiers 중복 없음")
    func allCases_noDuplicateMapping() {
        // 변경 불가 케이스만 — 변경 가능 6종 (SPM 동적 조회) 은 모두 keyCode=0 통일이라 중복 검사 의미 X.
        // TASK-036 — pageUp/Down (⌘) + moveSelectionToFirst/Last (⌘⇧) 는 moveSelectionUp/Down (단독) 과 동일 keyCode (126/125) 이되 modifiers 로 3-way 분기 (단독 / [.command] / [.command,.shift]), 중복 없음 검증.
        let fixedCases: [PopoverHotkey] = [.moveSelectionUp, .moveSelectionDown, .pageUp, .pageDown, .moveSelectionToFirst, .moveSelectionToLast, .escape]
        let pairs = fixedCases.map { ($0.keyCode, $0.modifiers.rawValue) }
        let seen = Set(pairs.map { "\($0.0)-\($0.1)" })
        #expect(seen.count == pairs.count, "변경 불가 PopoverHotkey 중 keyCode+modifiers 중복 정의 발견")
    }
}
