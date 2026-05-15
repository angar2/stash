// MockPasteboard — Pasteboard protocol 테스트용 in-memory 구현체
@testable import stash
import AppKit

final class MockPasteboard: stash.Pasteboard, @unchecked Sendable {
    var changeCount: Int = 0
    var strings: [NSPasteboard.PasteboardType: String] = [:]
    var dataStore: [NSPasteboard.PasteboardType: Data] = [:]
    var availableTypes: [NSPasteboard.PasteboardType] = []
    /// 검증용 — 호출 순서대로 기록 (PasteServiceTests에서 ClipType별 분기 호출 검증).
    var recordedSetString: [(String, NSPasteboard.PasteboardType)] = []
    var recordedSetData: [(Data, NSPasteboard.PasteboardType)] = []
    var recordedDeclareTypes: [[NSPasteboard.PasteboardType]] = []
    var recordedClearCount: Int = 0

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
        recordedSetString.append((string, dataType))
    }

    func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType) {
        dataStore[dataType] = data
        changeCount += 1
        recordedSetData.append((data, dataType))
    }

    func clearAndDeclareTypes(_ types: [NSPasteboard.PasteboardType]) {
        strings.removeAll()
        dataStore.removeAll()
        recordedClearCount += 1
        recordedDeclareTypes.append(types)
    }
}
