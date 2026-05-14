// MockLoginItemRegistrar — LoginItemRegistrar protocol 테스트용 구현체
@testable import stash

final class MockLoginItemRegistrar: LoginItemRegistrar, @unchecked Sendable {
    var registered = false
    var registerCallCount = 0
    var unregisterCallCount = 0
    var shouldThrow = false

    var isRegistered: Bool {
        get throws { registered }
    }

    func register() throws {
        if shouldThrow { throw MockError.forced }
        registered = true
        registerCallCount += 1
    }

    func unregister() throws {
        if shouldThrow { throw MockError.forced }
        registered = false
        unregisterCallCount += 1
    }
}

enum MockError: Error { case forced }
