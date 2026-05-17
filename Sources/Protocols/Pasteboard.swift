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

    /// TASK-026 — 시스템 클립보드의 다중 file URL 추출.
    /// `NSPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])` 래핑.
    /// 결과 nil/empty 시 nil 반환.
    func readFileURLs() -> [URL]?

    /// TASK-026 — 시스템 클립보드에 다중 file URL 박음.
    /// 내부에서 `clearContents()` + `writeObjects([NSURL])` 통합 (별도 clear 노출 X). Finder ⌘V 호환.
    func writeFileURLs(_ urls: [URL])
}
