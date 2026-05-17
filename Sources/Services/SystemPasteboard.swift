// Pasteboard protocol 준수 — NSPasteboard.general thin wrapper
import AppKit
import OSLog

final class SystemPasteboard: Pasteboard, @unchecked Sendable {
    static let shared = SystemPasteboard()
    private init() {}

    private var pb: NSPasteboard { NSPasteboard.general }

    var changeCount: Int { pb.changeCount }

    func availableType(from types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? {
        pb.availableType(from: types)
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        pb.data(forType: dataType)
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        pb.string(forType: dataType)
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) {
        _ = pb.setString(string, forType: dataType)
    }

    func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType) {
        _ = pb.setData(data, forType: dataType)
    }

    func clearAndDeclareTypes(_ types: [NSPasteboard.PasteboardType]) {
        pb.clearContents()
        pb.declareTypes(types, owner: nil)
    }

    /// TASK-026 — 시스템 클립보드의 다중 file URL 추출. file URL 만 필터 (web URL 제외).
    func readFileURLs() -> [URL]? {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: NSNumber(value: true)]
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else {
            return nil
        }
        return urls
    }

    /// TASK-026 — 시스템 클립보드에 다중 file URL 박음 (clear + declareTypes + writeObjects 통합). Finder ⌘V 호환.
    /// **수동 NSPasteboardItem 패턴** — `urls as [NSURL]` 자동 변환의 간헐적 race 회피.
    /// 각 URL을 explicit한 NSPasteboardItem으로 박아 `public.file-url` UTI 직접 설정. 단일 분기 `setString(.fileURL)` 패턴과 정합.
    /// 반환값 + pasteboardItems 박힌 수 검증 — silent fail 진단.
    func writeFileURLs(_ urls: [URL]) {
        pb.clearContents()
        pb.declareTypes([.fileURL], owner: nil)
        let items = urls.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        let success = pb.writeObjects(items)
        let writtenCount = pb.pasteboardItems?.count ?? 0
        if !success || writtenCount != urls.count {
            Logger.paste.error("writeFileURLs: silent fail risk — success=\(success) input=\(urls.count) items=\(writtenCount)")
        } else {
            Logger.paste.info("writeFileURLs: \(urls.count) URLs written successfully")
        }
    }
}
