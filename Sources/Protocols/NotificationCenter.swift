// UNUserNotificationCenter 추상화 protocol — Foundation.NotificationCenter와 구분
import Foundation

protocol StashNotificationCenter: Sendable {
    /// 시스템 알림 발송. 첫 호출 시 사용자 권한 자동 요청.
    /// 권한 거부 사용자는 알림 표시 안 됨 — silent fail + Logger 로깅.
    func send(_ notification: StashNotification) async
}
