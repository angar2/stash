// StashNotificationCenter protocol 준수 — UNUserNotificationCenter thin wrapper
import UserNotifications
import OSLog

actor UNNotificationCenterImpl: StashNotificationCenter {
    func send(_ notification: StashNotification) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            Logger.appLifecycle.info("Notification permission denied — skipping \(String(describing: notification))")
            return
        }
        let content = UNMutableNotificationContent()
        switch notification {
        case .dbCorruptionRecovered:
            content.title = "stash"
            content.body  = "클립보드 DB가 복구되었습니다."
        case .permissionGranted:
            content.title = "stash"
            content.body  = "손쉬운 사용 권한이 허용되었습니다."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
