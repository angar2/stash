// MockPermissionChecker — AccessibilityPermissionChecker protocol 테스트용 구현체
import Foundation
@testable import stash

final class MockPermissionChecker: AccessibilityPermissionChecker, @unchecked Sendable {
    var trusted = false
    var promptCallCount = 0
    /// TASK-115 — 상태 확인 호출 횟수. PermissionService actor 와 테스트 쪽이 함께 읽고 써서 잠금으로 감싼다.
    private let lock = NSLock()
    private var _checkCallCount = 0
    var checkCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _checkCallCount
    }

    func isTrusted(promptUserIfNeeded: Bool) -> Bool {
        if promptUserIfNeeded { promptCallCount += 1 }
        lock.lock(); _checkCallCount += 1; lock.unlock()
        return trusted
    }
}
