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
    /// TASK-026 fix — paste 진행 시작/종료 시 호출. Composition Root 가 `ClipboardWatcher.setPastePending(_:)` 주입.
    /// 다중 파일 paste의 saveFiles race 차단 — tick이 paste 도중 새 캡쳐 진입해 ack 대기 시간 증가하는 함정 fix.
    private let setPastePending: (@Sendable (Bool) async -> Void)?

    init(
        synthesizer: PasteSynthesizer,
        pasteboard: Pasteboard,
        repository: ClipRepository,
        permissionService: PermissionService,
        onPasteboardWritten: (@Sendable () async -> Void)? = nil,
        setPastePending: (@Sendable (Bool) async -> Void)? = nil
    ) {
        self.synthesizer = synthesizer
        self.pasteboard = pasteboard
        self.repository = repository
        self.permissionService = permissionService
        self.onPasteboardWritten = onPasteboardWritten
        self.setPastePending = setPastePending
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

        // TASK-026 fix — paste 진행 동안 watcher tick 자체 차단 (race 차단). 다중 파일의 saveFiles 시간 소요로 인한
        // ack 대기 → synthesizeCommandV 지연 함정 fix. begin 호출은 *write 전*, end 는 *모든 흐름 후* (try/catch finally 보장).
        await setPastePending?(true)
        do {
            try writeToPasteboard(clip: clip)

            // TASK-023 회귀 (e) fix — pasteboard 박은 직후 watcher 에 통보. synthesizer ⌘V 합성은 *읽기* 동작이라 추가 changeCount 증가 X, 콜백은 합성 전 호출 안전.
            await onPasteboardWritten?()

            if mode == .autoPaste {
                try synthesizer.synthesizeCommandV()
            }

            try await repository.updateLastUsedAt(id: clip.id)
            Logger.paste.info("Paste done: type=\(clip.type.rawValue, privacy: .public), mode=\(mode.rawValue, privacy: .public)")
            await setPastePending?(false)
        } catch {
            // TASK-026 fix — paste 실패 시에도 pending 해제 보장 (try/catch finally).
            await setPastePending?(false)
            throw error
        }
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
            // TASK-082 Phase 5 — autoreleasepool 안에 박아 NSImage + tiff/png Data 인스턴스 일시 회수 강제.
            // paste 흐름 끝나면 pool drain 시점에 풀해상도 backing store 즉시 회수 — autorelease 잔존 차단 (100MB+ 이미지 paste 시 메모리 잔존 영향 ↓).
            try autoreleasepool {
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
            }

        case .file:
            // TASK-026 — 다중 파일 묶음이면 별도 helper 위임 (writeImagePasteboard 형제 패턴).
            if clip.isMultiFile {
                try writeMultiFilePasteboard(clip)
                return
            }
            // 단일 파일 (기존 분기) — fileOriginalPath 우선, fallback filePath.
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

    /// TASK-026 — 다중 파일 묶음 paste 헬퍼. entries 디코드 + URL 배열 변환 + `pasteboard.writeFileURLs([URL])`.
    /// entry별 path 우선순위 = `originalPath ?? filePath` (단일 케이스 C/D 정합 — 원본 존재 시 원본 박음).
    /// 디코드 실패 / 빈 배열 → `PasteError.fileURLLoadFailed` throw.
    private func writeMultiFilePasteboard(_ clip: Clip) throws {
        guard let entries = clip.fileEntries, !entries.isEmpty else {
            Logger.paste.error("Paste failed: multi-file clip has invalid filePathsJson, clipId=\(clip.id.uuidString, privacy: .public)")
            throw PasteError.fileURLLoadFailed
        }
        let urls = entries.map { entry -> URL in
            let path = !entry.originalPath.isEmpty ? entry.originalPath : entry.filePath
            return URL(fileURLWithPath: path)
        }
        Logger.paste.info("Paste multi-file: \(urls.count) URLs")
        pasteboard.writeFileURLs(urls)
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
