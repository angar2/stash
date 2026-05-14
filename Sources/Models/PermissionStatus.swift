// Accessibility 권한 상태 enum (API-SPEC §2-2 정합)
import Foundation

enum PermissionStatus: Sendable {
    case granted
    case denied
    case unknown  // 앱 시작 직후 첫 polling 결과 도착 전 초기 상태
}
