// KeyboardShortcuts SPM을 래핑해 단축키 등록·해제·충돌 검사를 담당하는 서비스
import Foundation
import AppKit
import KeyboardShortcuts
import OSLog

@MainActor
final class HotkeyManager {
    enum ConflictResult: Equatable {
        case ok
        case noModifier
        case systemReserved(String)
    }

    private let registrar: HotkeyRegistrar
    private let permissionService: PermissionService
    private var registeredNames: Set<KeyboardShortcuts.Name> = []

    init(registrar: HotkeyRegistrar, permissionService: PermissionService) {
        self.registrar = registrar
        self.permissionService = permissionService
    }

    func register(name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        registrar.register(name: name, action: action)
        registeredNames.insert(name)
        Logger.hotkey.info("Registered shortcut: \(name.rawValue, privacy: .public)")
    }

    func unregister(name: KeyboardShortcuts.Name) {
        registrar.unregister(name: name)
        registeredNames.remove(name)
        Logger.hotkey.info("Unregistered shortcut: \(name.rawValue, privacy: .public)")
    }

    func unregisterAll() {
        let names = registeredNames
        for name in names {
            registrar.unregister(name: name)
        }
        registeredNames.removeAll()
        Logger.hotkey.info("Unregistered all \(names.count, privacy: .public) shortcuts")
    }

    /// 시스템 표준 단축키 / modifier 부재 여부 검사.
    /// - Returns: `.ok` 충돌 없음 / `.noModifier` modifier 없음 / `.systemReserved(label)` 시스템 표준 단축키와 충돌
    func validateNoConflict(shortcut: KeyboardShortcuts.Shortcut) -> ConflictResult {
        let meaningful: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        if shortcut.modifiers.intersection(meaningful).isEmpty {
            return .noModifier
        }
        if let label = Self.systemReservedShortcuts.first(where: { $0.0 == shortcut })?.1 {
            return .systemReserved(label)
        }
        return .ok
    }

    // macOS 표준 단축키 블랙리스트 — 사용자 단축키 설정 충돌 사전 차단용
    private static let systemReservedShortcuts: [(KeyboardShortcuts.Shortcut, String)] = [
        (.init(.c, modifiers: .command), "⌘C"),
        (.init(.v, modifiers: .command), "⌘V"),
        (.init(.x, modifiers: .command), "⌘X"),
        (.init(.z, modifiers: .command), "⌘Z"),
        (.init(.z, modifiers: [.command, .shift]), "⌘⇧Z"),
        (.init(.q, modifiers: .command), "⌘Q"),
        (.init(.w, modifiers: .command), "⌘W"),
        (.init(.a, modifiers: .command), "⌘A"),
        (.init(.s, modifiers: .command), "⌘S"),
        (.init(.f, modifiers: .command), "⌘F"),
        (.init(.n, modifiers: .command), "⌘N"),
        (.init(.p, modifiers: .command), "⌘P"),
        (.init(.t, modifiers: .command), "⌘T"),
        (.init(.o, modifiers: .command), "⌘O"),
        (.init(.r, modifiers: .command), "⌘R"),
        (.init(.tab, modifiers: .command), "⌘⇥"),
        (.init(.space, modifiers: .command), "⌘Space"),
        (.init(.comma, modifiers: .command), "⌘,"),
    ]
}
