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

    // TASK-090 — `StashApp.swift` 잔존 fallback (`⌘⇧V` 강제 setShortcut) 제거 후
    // `.popoverOpen` default 적용은 `registerDefaultsIfNeeded()` 단일 진실 진입점이 담당.
    // SPM 키 클린 상태(신규 설치 시뮬) → `registerDefaultsIfNeeded()` 호출 → `.popoverOpen` 이
    // `defaults[.popoverOpen]` (`⌘⇧C`) 로 박혀야 함. 회귀 시 ⌘⇧V 잔존 fallback 재발 차단.
    @Test("TASK-090 — registerDefaultsIfNeeded 가 .popoverOpen 에 ⌘⇧C 등록 (SPM 키 클린 상태)")
    func registerDefaults_popoverOpen_appliesShiftCommandC() {
        // setup — SPM 잔존 키 제거. KeyboardShortcuts SPM 내부 키 형식 = `KeyboardShortcuts_{name}`.
        // `KeyboardShortcuts.Name` 인스턴스 raw value = `"stash.popoverOpen"` → 실제 UserDefaults 키 = `"KeyboardShortcuts_stash.popoverOpen"`.
        let spmKey = "KeyboardShortcuts_stash.popoverOpen"
        UserDefaults.standard.removeObject(forKey: spmKey)

        // act
        PopoverShortcutStore.registerDefaultsIfNeeded()

        // assert
        let shortcut = PopoverShortcutStore.get(.popoverOpen)
        #expect(shortcut != nil, "registerDefaultsIfNeeded 후 .popoverOpen 미등록")
        #expect(shortcut?.keyCode == 8, "popoverOpen keyCode = 8 (C), got \(String(describing: shortcut?.keyCode))")
        let mods: NSEvent.ModifierFlags = [.command, .shift]
        #expect(shortcut?.modifiersRawValue == mods.rawValue, "popoverOpen modifiers = [.command, .shift]")
    }
}
