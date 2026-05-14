// MockNotificationCenter — StashNotificationCenter protocol 테스트용 구현체
@testable import stash

final class MockNotificationCenter: StashNotificationCenter, @unchecked Sendable {
    var sentNotifications: [StashNotification] = []

    func send(_ notification: StashNotification) async {
        sentNotifications.append(notification)
    }
}
