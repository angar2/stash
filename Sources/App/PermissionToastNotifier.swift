// 권한 부여 감지 시 popover 인라인 토스트 + 시스템 알림 1회 병행 발행 (UX-UI §6 / TASK-015 Phase 10 정합)
import Foundation
import Combine
import OSLog

@MainActor
final class PermissionToastNotifier {
    private var cancellable: AnyCancellable?
    private let toastQueue: ToastQueue
    private let notificationService: NotificationService
    private var lastStatus: PermissionStatus = .unknown

    init(
        publisher: AnyPublisher<PermissionStatus, Never>,
        toastQueue: ToastQueue,
        notificationService: NotificationService
    ) {
        self.toastQueue = toastQueue
        self.notificationService = notificationService
        cancellable = publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handle(status: status)
            }
    }

    private func handle(status: PermissionStatus) {
        defer { lastStatus = status }
        guard status == .granted && lastStatus != .granted else { return }
        // TASK-066 — i18n 키 dotted rename (toast.permissionGranted → toast.permission.granted) + ttl 자동 추종.
        toastQueue.enqueue(.success, L10n("toast.permission.granted"))
        let notified = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.permissionGrantedNotified)
        if !notified {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.permissionGrantedNotified)
            Task { [notificationService] in
                await notificationService.notify(.permissionGranted)
                Logger.permission.info("System notification 발송 — 권한 부여 1회 정책")
            }
        }
    }
}
