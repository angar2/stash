// MockPasteboard — Pasteboard protocol 테스트용 in-memory 구현체
@testable import stash
import AppKit

final class MockPasteboard: stash.Pasteboard, @unchecked Sendable {
    var changeCount: Int = 0
    var strings: [NSPasteboard.PasteboardType: String] = [:]
    var dataStore: [NSPasteboard.PasteboardType: Data] = [:]
    var availableTypes: [NSPasteboard.PasteboardType] = []

    func availableType(from types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? {
        types.first { availableTypes.contains($0) }
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        dataStore[dataType]
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        strings[dataType]
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) {
        strings[dataType] = string
        changeCount += 1
    }
}
