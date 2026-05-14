// MockPasteSynthesizer — PasteSynthesizer protocol 테스트용 구현체
@testable import stash

final class MockPasteSynthesizer: PasteSynthesizer, @unchecked Sendable {
    var shouldThrow = false
    var callCount = 0

    func synthesizeCommandV() throws {
        callCount += 1
        if shouldThrow { throw PasteError.keyboardSimulationFailed }
    }
}
