// MockPasteSynthesizer — PasteSynthesizer protocol 테스트용 구현체
@testable import stash

final class MockPasteSynthesizer: PasteSynthesizer, @unchecked Sendable {
    var shouldThrow = false
    var callCount = 0
    var onSynthesize: (@Sendable () -> Void)?

    func synthesizeCommandV() throws {
        callCount += 1
        onSynthesize?()
        if shouldThrow { throw PasteError.keyboardSimulationFailed }
    }
}
