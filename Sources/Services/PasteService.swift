// CGEvent ⌘V 합성으로 자동 붙여넣기를 수행하는 서비스 — auto-paste / copy back 분기
// ClipType별 분기: .text → setString(.string) / .image → setData(.tiff or .png) / .file → setString(.fileURL)
import Foundation
import AppKit
import OSLog

@MainActor
final class PasteService {
    private let synthesizer: PasteSynthesizer
    private let pasteboard: Pasteboard
    private let repository: ClipRepository
    private let permissionService: PermissionService
    /// pasteboard 박기 직후 호출되는 콜백 — Composition Root 가 `ClipboardWatcher.acknowledgeOwnWrite()` 주입해 self-write skip 트리거 (TASK-023 회귀 (e) fix).
    private let onPasteboardWritten: (@Sendable () async -> Void)?

    init(
        synthesizer: PasteSynthesizer,
        pasteboard: Pasteboard,
        repository: ClipRepository,
        permissionService: PermissionService,
        onPasteboardWritten: (@Sendable () async -> Void)? = nil
    ) {
        self.synthesizer = synthesizer
        self.pasteboard = pasteboard
        self.repository = repository
        self.permissionService = permissionService
        self.onPasteboardWritten = onPasteboardWritten
    }

    /// 클립 paste — ClipType 분기 + mode (auto-paste / copy back) 분기.
    /// - .autoPaste: setString/setData → ⌘V 합성 → last_used_at 갱신
    /// - .copyBack: setString/setData → last_used_at 갱신 (합성 skip)
    /// - 합성 실패 시 `PasteError.keyboardSimulationFailed` 전파 + last_used_at 미갱신 (정렬 rollback)
    /// - ClipType별 데이터 누락 시 PasteError 분기:
    ///   - text body=nil → .unsupportedClipPayload
    ///   - image filePath=nil 또는 NSImage 로드 실패 → .imageDataLoadFailed
    ///   - file fileOriginalPath/filePath 모두 nil → .fileURLLoadFailed
    func paste(clip: Clip, mode: PasteMode) async throws {
        Logger.paste.info("Paste start: type=\(clip.type.rawValue, privacy: .public), mode=\(mode.rawValue, privacy: .public), clipId=\(clip.id.uuidString, privacy: .public)")

        try writeToPasteboard(clip: clip)

        // TASK-023 회귀 (e) fix — pasteboard 박은 직후 watcher 에 통보. synthesizer ⌘V 합성은 *읽기* 동작이라 추가 changeCount 증가 X, 콜백은 합성 전 호출 안전.
        await onPasteboardWritten?()

        if mode == .autoPaste {
            try synthesizer.synthesizeCommandV()
        }

        try await repository.updateLastUsedAt(id: clip.id)
        Logger.paste.info("Paste done: type=\(clip.type.rawValue, privacy: .public), mode=\(mode.rawValue, privacy: .public)")
    }

    /// ClipType별 NSPasteboard 쓰기 분기 — text / image / file.
    private func writeToPasteboard(clip: Clip) throws {
        switch clip.type {
        case .text:
            guard let body = clip.body else {
                Logger.paste.error("Paste failed: text clip has nil body, clipId=\(clip.id.uuidString, privacy: .public)")
                throw PasteError.unsupportedClipPayload
            }
            pasteboard.clearAndDeclareTypes([.string])
            pasteboard.setString(body, forType: .string)

        case .image:
            guard let filePath = clip.filePath else {
                Logger.paste.error("Paste failed: image clip has nil filePath, clipId=\(clip.id.uuidString, privacy: .public)")
                throw PasteError.imageDataLoadFailed
            }
            let url = URL(fileURLWithPath: filePath)
            guard let nsImage = NSImage(contentsOf: url) else {
                Logger.paste.error("Paste failed: NSImage load failed at \(filePath, privacy: .public)")
                throw PasteError.imageDataLoadFailed
            }
            // TASK-023 사용자 검수 회귀 (d) — Finder 폴더 ⌘V 호환을 위해 fileOriginalPath 있고 *파일 실재* 시 file URL 도 함께 박음.
            // 메모리 비트맵(스크린샷 / 브라우저 이미지 우클릭 복사) 은 fileOriginalPath nil → image data 만 (기존 동작).
            let originalFileURL = clip.fileOriginalPath
                .flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }

            // TIFF 우선 — 가장 호환성 높음. 실패 시 PNG fallback.
            if let tiffData = nsImage.tiffRepresentation {
                writeImagePasteboard(data: tiffData, dataType: .tiff, originalFileURL: originalFileURL)
            } else if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
                writeImagePasteboard(data: pngData, dataType: .png, originalFileURL: originalFileURL)
            } else {
                Logger.paste.error("Paste failed: NSImage neither TIFF nor PNG representation available")
                throw PasteError.imageDataLoadFailed
            }

        case .file:
            // 외부 파일은 fileOriginalPath 우선 (사용자 원본 위치). 내부 보관본은 filePath fallback.
            let pathString = clip.fileOriginalPath ?? clip.filePath
            guard let path = pathString else {
                Logger.paste.error("Paste failed: file clip has nil fileOriginalPath and filePath, clipId=\(clip.id.uuidString, privacy: .public)")
                throw PasteError.fileURLLoadFailed
            }
            let url = URL(fileURLWithPath: path)
            // public.file-url — NSURL 표준 방식, Finder / Mail 모두 인식.
            let fileURLType = NSPasteboard.PasteboardType("public.file-url")
            pasteboard.clearAndDeclareTypes([fileURLType])
            pasteboard.setString(url.absoluteString, forType: fileURLType)
        }
    }

    /// `.image` 분기 헬퍼 — image data 단일 타입 박음 + `originalFileURL` 박혀있으면 `public.file-url` 동시 박음 (Finder 폴더 ⌘V 호환).
    /// TIFF / PNG fallback 두 경로의 *declare + setData + (선택) setString + 로그* 공통 흐름 추출 (TASK-023 리팩토링).
    private func writeImagePasteboard(data: Data, dataType: NSPasteboard.PasteboardType, originalFileURL: URL?) {
        var declaredTypes: [NSPasteboard.PasteboardType] = [dataType]
        if originalFileURL != nil { declaredTypes.append(.fileURL) }
        pasteboard.clearAndDeclareTypes(declaredTypes)
        pasteboard.setData(data, forType: dataType)
        if let originalFileURL {
            pasteboard.setString(originalFileURL.absoluteString, forType: .fileURL)
            Logger.paste.info("Paste image clip with file URL (\(dataType.rawValue, privacy: .public)): \(originalFileURL.path, privacy: .public)")
        }
    }
}
