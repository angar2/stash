// CGEvent ⌘V 합성으로 자동 붙여넣기를 수행하는 서비스 — auto-paste / copy back 분기
import Foundation
import AppKit
import OSLog

@MainActor
final class PasteService {
    private let synthesizer: PasteSynthesizer
    private let pasteboard: Pasteboard
    private let repository: ClipRepository
    private let permissionService: PermissionService

    init(
        synthesizer: PasteSynthesizer,
        pasteboard: Pasteboard,
        repository: ClipRepository,
        permissionService: PermissionService
    ) {
        self.synthesizer = synthesizer
        self.pasteboard = pasteboard
        self.repository = repository
        self.permissionService = permissionService
    }

    /// 클립 paste — mode 에 따라 auto-paste / copy back 분기.
    /// - .autoPaste: setString → ⌘V 합성 → last_used_at 갱신
    /// - .copyBack: setString → last_used_at 갱신 (합성 skip)
    /// - 합성 실패 시 `PasteError.keyboardSimulationFailed` 전파 + last_used_at 미갱신 (정렬 rollback)
    func paste(clip: Clip, mode: PasteMode) async throws {
        Logger.paste.info("Paste start: mode=\(mode.rawValue, privacy: .public), clipId=\(clip.id.uuidString, privacy: .public)")

        pasteboard.setString(clip.body ?? "", forType: .string)

        if mode == .autoPaste {
            try synthesizer.synthesizeCommandV()
        }

        try await repository.updateLastUsedAt(id: clip.id)
        Logger.paste.info("Paste done: mode=\(mode.rawValue, privacy: .public)")
    }
}
