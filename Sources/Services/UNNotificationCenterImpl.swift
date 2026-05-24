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
            content.title = "Stash"
            content.body  = L10n("notification.dbRecovered.body")
        case .permissionGranted:
            content.title = "Stash"
            content.body  = L10n("notification.permissionGranted.body")
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
