// UserNotifications 시스템 알림 발송을 담당하는 actor
import Foundation

actor NotificationService {
    private let center: StashNotificationCenter

    init(center: StashNotificationCenter) {
        self.center = center
    }

    func notify(_ notification: StashNotification) async {
        await center.send(notification)
    }
}
