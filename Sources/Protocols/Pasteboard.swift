// NSPasteboard 추상화 protocol — 클립보드 읽기/쓰기 테스트 가능성 확보
import AppKit

protocol Pasteboard: Sendable {
    var changeCount: Int { get }
    func availableType(from types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType?
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType)
    /// 이미지/파일 등 binary 데이터 set — 호출 전 declareTypes로 타입 등록 필수.
    func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType)
    /// 클립보드를 비우고 사용할 타입을 등록 (NSPasteboard.clearContents + declareTypes).
    func clearAndDeclareTypes(_ types: [NSPasteboard.PasteboardType])
}
