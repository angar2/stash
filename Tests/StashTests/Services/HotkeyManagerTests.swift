// HotkeyManager — register/unregister 추적 + validateNoConflict 분기 검증
@testable import stash
import Testing
import KeyboardShortcuts
import AppKit

@Suite("HotkeyManager")
@MainActor
struct HotkeyManagerTests {

    // MARK: - Helpers

    private func makeManager(
        registrar: MockHotkeyRegistrar = MockHotkeyRegistrar()
    ) -> (HotkeyManager, MockHotkeyRegistrar) {
        let mgr = HotkeyManager(registrar: registrar, permissionService: PermissionService(checker: MockPermissionChecker()))
        return (mgr, registrar)
    }

    private static let nameA = KeyboardShortcuts.Name("test.a")
    private static let nameB = KeyboardShortcuts.Name("test.b")
    private static let nameC = KeyboardShortcuts.Name("test.c")

    // MARK: - register / unregister

    @Test func registerAddsName() {
        let (mgr, mock) = makeManager()
        mgr.register(name: Self.nameA) {}
        #expect(mock.registeredNames.contains(Self.nameA))
    }

    @Test func unregisterRemovesName() {
        let (mgr, mock) = makeManager()
        mgr.register(name: Self.nameA) {}
        mgr.unregister(name: Self.nameA)
        #expect(mock.unregisteredNames.contains(Self.nameA))
    }

    @Test func unregisterAllRemovesEveryRegisteredName() {
        let (mgr, mock) = makeManager()
        mgr.register(name: Self.nameA) {}
        mgr.register(name: Self.nameB) {}
        mgr.register(name: Self.nameC) {}
        mgr.unregisterAll()
        #expect(Set(mock.unregisteredNames) == Set([Self.nameA, Self.nameB, Self.nameC]))
    }

    // MARK: - validateNoConflict

    @Test func validateNoConflictReturnsNoModifierWhenModifiersEmpty() {
        let (mgr, _) = makeManager()
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [])
        #expect(mgr.validateNoConflict(shortcut: shortcut) == .noModifier)
    }

    @Test func validateNoConflictRejectsCommandC() {
        let (mgr, _) = makeManager()
        let shortcut = KeyboardShortcuts.Shortcut(.c, modifiers: .command)
        #expect(mgr.validateNoConflict(shortcut: shortcut) == .systemReserved("⌘C"))
    }

    @Test func validateNoConflictAcceptsCommandShiftH() {
        let (mgr, _) = makeManager()
        let shortcut = KeyboardShortcuts.Shortcut(.h, modifiers: [.command, .shift])
        #expect(mgr.validateNoConflict(shortcut: shortcut) == .ok)
    }

    @Test func validateNoConflictRejectsCommandShiftZ() {
        let (mgr, _) = makeManager()
        let shortcut = KeyboardShortcuts.Shortcut(.z, modifiers: [.command, .shift])
        #expect(mgr.validateNoConflict(shortcut: shortcut) == .systemReserved("⌘⇧Z"))
    }
}
