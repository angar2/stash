// NotificationService — notify() 위임 동작 검증
@testable import stash
import Testing

@Suite("NotificationService")
@MainActor
struct NotificationServiceTests {

    private func makeService(mock: MockNotificationCenter = MockNotificationCenter()) -> (NotificationService, MockNotificationCenter) {
        let svc = NotificationService(center: mock)
        return (svc, mock)
    }

    @Test func notifyDbCorruptionDelegatesToCenter() async {
        let (svc, mock) = makeService()
        await svc.notify(.dbCorruptionRecovered)
        #expect(mock.sentNotifications == [.dbCorruptionRecovered])
    }

    @Test func notifyPermissionGrantedDelegatesToCenter() async {
        let (svc, mock) = makeService()
        await svc.notify(.permissionGranted)
        #expect(mock.sentNotifications == [.permissionGranted])
    }

    @Test func notifyMultipleCallsPreservesOrder() async {
        let (svc, mock) = makeService()
        await svc.notify(.dbCorruptionRecovered)
        await svc.notify(.permissionGranted)
        #expect(mock.sentNotifications.count == 2)
        #expect(mock.sentNotifications[0] == .dbCorruptionRecovered)
        #expect(mock.sentNotifications[1] == .permissionGranted)
    }
}
