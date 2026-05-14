// 글로벌 단축키 등록·해제 추상화 protocol — KeyboardShortcuts SPM wrap
import KeyboardShortcuts

protocol HotkeyRegistrar: Sendable {
    func register(name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void)
    func unregister(name: KeyboardShortcuts.Name)
}
