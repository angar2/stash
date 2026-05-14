// MockLoginItemRegistrar — LoginItemRegistrar protocol 테스트용 구현체
@testable import stash

final class MockLoginItemRegistrar: LoginItemRegistrar, @unchecked Sendable {
    var registered = false
    var registerCallCount = 0
    var unregisterCallCount = 0

    var isRegistered: Bool {
        get throws { registered }
    }

    func register() throws {
        registered = true
        registerCallCount += 1
    }

    func unregister() throws {
        registered = false
        unregisterCallCount += 1
    }
}
