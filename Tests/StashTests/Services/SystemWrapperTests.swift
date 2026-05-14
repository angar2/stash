// 시스템 Wrapper protocol Mock 단위 테스트 — 7 Mock 동작 검증
@testable import stash
import Testing
import Foundation
import AppKit
import KeyboardShortcuts

@Suite("SystemWrapper Mocks")
struct SystemWrapperTests {

    @Test func mockPasteboardSetAndGetString() {
        let pb = MockPasteboard()
        pb.setString("hello", forType: .string)
        #expect(pb.string(forType: .string) == "hello")
        #expect(pb.changeCount == 1)
    }

    @Test func mockPasteboardAvailableType() {
        let pb = MockPasteboard()
        pb.availableTypes = [.string]
        #expect(pb.availableType(from: [.string]) == .string)
        #expect(pb.availableType(from: [.tiff]) == nil)
    }

    @Test func mockHotkeyRegistrarRegisterAndUnregister() {
        let reg = MockHotkeyRegistrar()
        let name = KeyboardShortcuts.Name("testShortcut_\(UUID().uuidString)")
        reg.register(name: name, action: {})
        #expect(reg.registeredNames.count == 1)
        reg.unregister(name: name)
        #expect(reg.registeredNames.isEmpty)
        #expect(reg.unregisteredNames.count == 1)
    }

    @Test func mockPasteSynthesizerSuccess() throws {
        let synth = MockPasteSynthesizer()
        try synth.synthesizeCommandV()
        #expect(synth.callCount == 1)
    }

    @Test func mockPasteSynthesizerThrows() {
        let synth = MockPasteSynthesizer()
        synth.shouldThrow = true
        do {
            try synth.synthesizeCommandV()
            Issue.record("Expected keyboardSimulationFailed to be thrown")
        } catch PasteError.keyboardSimulationFailed {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func mockFileClipServiceSaveData() async throws {
        let svc = MockFileClipService()
        let data = Data("test".utf8)
        let stored = try await svc.saveData(data, type: .text)
        #expect(!stored.isFileExternal)
        #expect(svc.savedFiles.count == 1)
    }

    @Test func mockFileClipServiceDelete() async throws {
        let svc = MockFileClipService()
        let clip = ClipFixture.makeText()
        try await svc.delete(clip)
        #expect(svc.deletedClips.count == 1)
    }

    @Test func mockPermissionCheckerReturnsTrusted() {
        let checker = MockPermissionChecker()
        checker.trusted = true
        #expect(checker.isTrusted(promptUserIfNeeded: false) == true)
        #expect(checker.promptCallCount == 0)
    }

    @Test func mockNotificationCenterSend() async {
        let center = MockNotificationCenter()
        await center.send(.dbCorruptionRecovered)
        await center.send(.permissionGranted)
        #expect(center.sentNotifications.count == 2)
    }

    @Test func mockLoginItemRegistrarLifecycle() throws {
        let reg = MockLoginItemRegistrar()
        #expect(try reg.isRegistered == false)
        try reg.register()
        #expect(try reg.isRegistered == true)
        #expect(reg.registerCallCount == 1)
        try reg.unregister()
        #expect(try reg.isRegistered == false)
        #expect(reg.unregisterCallCount == 1)
    }
}
