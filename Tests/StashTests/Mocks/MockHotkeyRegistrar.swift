// MockHotkeyRegistrar — HotkeyRegistrar protocol 테스트용 구현체
@testable import stash
import KeyboardShortcuts

final class MockHotkeyRegistrar: HotkeyRegistrar, @unchecked Sendable {
    var registeredNames: [KeyboardShortcuts.Name] = []
    var unregisteredNames: [KeyboardShortcuts.Name] = []

    func register(name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        registeredNames.append(name)
    }

    func unregister(name: KeyboardShortcuts.Name) {
        registeredNames.removeAll { $0 == name }
        unregisteredNames.append(name)
    }
}
