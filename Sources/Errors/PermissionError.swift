// Accessibility 권한 에러 도메인 (API-SPEC §5 정합)
import Foundation

enum PermissionError: Error, Sendable {
    case accessibilityNotGranted
    case userDeniedRecovery
}

extension PermissionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return L10n("error.permission.accessibility_not_granted")
        case .userDeniedRecovery:
            return L10n("error.permission.user_denied_recovery")
        }
    }
}
