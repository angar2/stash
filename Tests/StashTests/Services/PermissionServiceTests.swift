// PermissionService — 6 API 동작 + statusPublisher 발행 + polling lifecycle 검증
@testable import stash
import Testing
import Foundation
import Combine

@Suite("PermissionService")
struct PermissionServiceTests {

    // MARK: - Helpers

    private func makeService(trusted: Bool = false) -> (PermissionService, MockPermissionChecker) {
        let checker = MockPermissionChecker()
        checker.trusted = trusted
        let svc = PermissionService(checker: checker)
        return (svc, checker)
    }

    // MARK: - 초기 상태

    @Test func initialStatusIsUnknown() async {
        let (svc, _) = makeService()
        let status = await svc.currentStatus()
        #expect(status == .unknown)
    }

    // MARK: - recheck 분기

    @Test func recheckGrantedTransitionsToGranted() async {
        let (svc, _) = makeService(trusted: true)
        await svc.recheck()
        let status = await svc.currentStatus()
        #expect(status == .granted)
    }

    @Test func recheckDeniedTransitionsToDenied() async {
        let (svc, _) = makeService(trusted: false)
        await svc.recheck()
        let status = await svc.currentStatus()
        #expect(status == .denied)
    }

    // MARK: - statusPublisher 발행 (구독 즉시 + recheck 결과 도착)

    @Test func statusPublisherEmitsCurrentValueAndUpdates() async throws {
        let (svc, _) = makeService(trusted: true)
        let received = LockedStatuses()

        let cancellable = svc.statusPublisher
            .sink { status in received.append(status) }

        await svc.recheck()
        try await Task.sleep(for: .milliseconds(50))

        cancellable.cancel()
        let values = received.snapshot()
        #expect(values.contains(.unknown))
        #expect(values.contains(.granted))
    }

    // MARK: - 동일 값 send 안 함 (스팸 방지)

    @Test func recheckDoesNotEmitDuplicate() async throws {
        let (svc, _) = makeService(trusted: false)
        let received = LockedStatuses()

        let cancellable = svc.statusPublisher
            .sink { status in received.append(status) }

        await svc.recheck()
        await svc.recheck()
        try await Task.sleep(for: .milliseconds(50))

        cancellable.cancel()
        let values = received.snapshot()
        // 구독 즉시 .unknown 1회 + recheck로 .denied 1회 = 총 2회. .denied 중복 발행 X.
        let deniedCount = values.filter { $0 == .denied }.count
        #expect(deniedCount == 1)
    }

    // MARK: - polling lifecycle (idempotent start + 재시작 정상)

    @Test func startOnboardingPollingLifecycleIsIdempotentAndRestartable() async {
        let (svc, _) = makeService(trusted: false)
        // start 2회 — 두 번째는 no-op
        await svc.startOnboardingPolling()
        await svc.startOnboardingPolling()
        // stop
        await svc.stopOnboardingPolling()
        // restart — 정상 재시작 가능
        await svc.startOnboardingPolling()
        await svc.stopOnboardingPolling()
        // 에러 없이 도달 = PASS
    }
}

/// Combine sink closure 안 외부 상태 누적용 (Sendable closure 격리).
private final class LockedStatuses: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PermissionStatus] = []

    func append(_ s: PermissionStatus) {
        lock.lock(); defer { lock.unlock() }
        values.append(s)
    }

    func snapshot() -> [PermissionStatus] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
