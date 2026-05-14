// 붙여넣기 합성 에러 도메인 (API-SPEC §5 정합)
import Foundation

enum PasteError: Error, Sendable {
    case noActiveApplication
    case keyboardSimulationFailed
    case clipboardWriteRollback
}

extension PasteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noActiveApplication:
            return String(localized: "error.paste.no_active_application")
        case .keyboardSimulationFailed:
            return String(localized: "error.paste.keyboard_simulation_failed")
        case .clipboardWriteRollback:
            return String(localized: "error.paste.clipboard_write_rollback")
        }
    }
}
