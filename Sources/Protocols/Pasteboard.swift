// NSPasteboard 추상화 protocol — 클립보드 읽기/쓰기 테스트 가능성 확보
import AppKit

protocol Pasteboard: Sendable {
    var changeCount: Int { get }
    func availableType(from types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType?
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType)
}
