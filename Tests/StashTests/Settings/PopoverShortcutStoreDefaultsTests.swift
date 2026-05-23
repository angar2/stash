// TASK-065 — PopoverShortcutStore.defaults 단축키 default 매핑 검증 (보관함 열기 ⌘⇧V → ⌘⇧C 정합)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverShortcutStore.defaults (TASK-065)")
struct PopoverShortcutStoreDefaultsTests {

    @Test("TASK-065 — popoverOpen default = ⌘⇧C (keyCode 8 + .command + .shift)")
    func popoverOpenDefault() {
        let def = PopoverShortcutStore.defaults[.popoverOpen]
        #expect(def != nil, "defaults 에 .popoverOpen 미등록")
        #expect(def?.keyCode == 8, "popoverOpen keyCode = 8 (C), got \(String(describing: def?.keyCode))")
        let mods: NSEvent.ModifierFlags = [.command, .shift]
        #expect(def?.modifiersRawValue == mods.rawValue, "popoverOpen modifiers = [.command, .shift]")
    }

    @Test("default 매핑 7항목 모두 등록 (regression 가드)")
    func allDefaultsRegistered() {
        for id in PopoverShortcutID.allCases {
            #expect(PopoverShortcutStore.defaults[id] != nil, "\(id.rawValue) default 미등록")
        }
    }
}
