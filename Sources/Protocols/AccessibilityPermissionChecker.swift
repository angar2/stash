// AXIsProcessTrustedWithOptions 추상화 protocol
import Foundation

protocol AccessibilityPermissionChecker: Sendable {
    /// 현재 Accessibility 권한 상태.
    /// - Parameter promptUserIfNeeded: true 면 시스템 권한 요청 다이얼로그 표시.
    func isTrusted(promptUserIfNeeded: Bool) -> Bool
}
