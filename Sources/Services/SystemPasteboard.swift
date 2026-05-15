// Pasteboard protocol 준수 — NSPasteboard.general thin wrapper
import AppKit

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
}
