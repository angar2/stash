// LoginItemService — isEnabled / setEnabled 동작 + 에러 전파 검증
@testable import stash
import Testing

@Suite("LoginItemService")
@MainActor
struct LoginItemServiceTests {

    private func makeService(registered: Bool = false, shouldThrow: Bool = false) -> (LoginItemService, MockLoginItemRegistrar) {
        let mock = MockLoginItemRegistrar()
        mock.registered = registered
        mock.shouldThrow = shouldThrow
        let svc = LoginItemService(registrar: mock)
        return (svc, mock)
    }

    @Test func isEnabledTrueWhenRegistrarRegistered() throws {
        let (svc, _) = makeService(registered: true)
        #expect(try svc.isEnabled == true)
    }

    @Test func isEnabledFalseWhenRegistrarNotRegistered() throws {
        let (svc, _) = makeService(registered: false)
        #expect(try svc.isEnabled == false)
    }

    @Test func setEnabledTrueCallsRegister() throws {
        let (svc, mock) = makeService()
        try svc.setEnabled(true)
        #expect(mock.registerCallCount == 1)
        #expect(mock.registered == true)
    }

    @Test func setEnabledFalseCallsUnregister() throws {
        let (svc, mock) = makeService(registered: true)
        try svc.setEnabled(false)
        #expect(mock.unregisterCallCount == 1)
        #expect(mock.registered == false)
    }

    @Test func setEnabledThrowsWhenRegistrarThrows() throws {
        let (svc, _) = makeService(shouldThrow: true)
        #expect(throws: MockError.self) {
            try svc.setEnabled(true)
        }
    }
}
