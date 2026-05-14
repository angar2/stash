// Accessibility 권한 상태를 polling으로 감지해 Publisher로 발행하는 actor
import Foundation
import Combine
import OSLog

actor PermissionService {
    private let checker: AccessibilityPermissionChecker
    // CurrentValueSubject는 내부 락으로 thread-safe하지만 Swift 6 Sendable 부합 X — nonisolated(unsafe) 명시.
    nonisolated(unsafe) private let subject = CurrentValueSubject<PermissionStatus, Never>(.unknown)
    private var pollingTask: Task<Void, Never>?

    init(checker: AccessibilityPermissionChecker) {
        self.checker = checker
    }

    /// 현재 권한 상태 stream (read-only) — UI / HotkeyManager / PasteService / NotificationService 다중 구독.
    nonisolated var statusPublisher: AnyPublisher<PermissionStatus, Never> {
        subject.eraseToAnyPublisher()
    }

    func currentStatus() -> PermissionStatus {
        subject.value
    }

    /// onboarding 2단계 진행 동안 1초 주기 polling 시작. 이미 진행 중이면 no-op.
    func startOnboardingPolling() {
        guard pollingTask == nil else { return }
        Logger.permission.info("Onboarding polling started")
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Constants.permissionPollingIntervalOnboarding)
                await self?.recheck()
            }
        }
    }

    /// onboarding polling 정지. 재호출 가능.
    func stopOnboardingPolling() {
        guard pollingTask != nil else { return }
        Logger.permission.info("Onboarding polling stopped")
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 권한 즉시 검사 + 변경 시에만 발행 (동일 값 스팸 방지).
    func recheck() async {
        let granted = checker.isTrusted(promptUserIfNeeded: false)
        let newStatus: PermissionStatus = granted ? .granted : .denied
        guard newStatus != subject.value else { return }
        Logger.permission.info("Permission status changed: \(String(describing: newStatus), privacy: .public)")
        subject.send(newStatus)
    }
}
