// HotkeyRegistrar protocol 준수 — KeyboardShortcuts SPM thin wrapper
import KeyboardShortcuts

struct KeyboardShortcutsRegistrar: HotkeyRegistrar {
    static let shared = KeyboardShortcutsRegistrar()

    func register(name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name) {
            Task { @MainActor in action() }
        }
    }

    func unregister(name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.reset(name)
    }
}
