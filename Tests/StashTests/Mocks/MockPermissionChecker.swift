// MockPermissionChecker — AccessibilityPermissionChecker protocol 테스트용 구현체
@testable import stash

final class MockPermissionChecker: AccessibilityPermissionChecker, @unchecked Sendable {
    var trusted = false
    var promptCallCount = 0

    func isTrusted(promptUserIfNeeded: Bool) -> Bool {
        if promptUserIfNeeded { promptCallCount += 1 }
        return trusted
    }
}
