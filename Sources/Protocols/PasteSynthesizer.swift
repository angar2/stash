// CGEvent ⌘V 합성 추상화 protocol
import Foundation

protocol PasteSynthesizer: Sendable {
    /// ⌘V 키 다운/업 합성.
    /// - Throws: `PasteError.keyboardSimulationFailed` (CGEvent 생성·전송 실패).
    func synthesizeCommandV() throws
}
