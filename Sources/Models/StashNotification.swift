// 앱 내부 알림 타입 enum — UX-UI §10 시스템 알림 2종 (API-SPEC §2-3 정합)
import Foundation

enum StashNotification: Sendable {
    case dbCorruptionRecovered
    case permissionGranted
}
