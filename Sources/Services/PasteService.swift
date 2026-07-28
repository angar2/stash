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
    /// TASK-099 — 혼합 묶음 사이 지연. 프로덕션은 `Constants` 값을 쓰고, 단위 테스트는 짧은 값을 넣는다.
    /// 테스트가 실제로 수백 ms 를 자면 병렬로 도는 *임계 시간에 의존하는 다른 테스트* 들을 굶겨 불안정해진다.
    private let sequentialDelay: Duration

    init(
        synthesizer: PasteSynthesizer,
        pasteboard: Pasteboard,
        repository: ClipRepository,
        permissionService: PermissionService,
        onPasteboardWritten: (@Sendable () async -> Void)? = nil,
        setPastePending: (@Sendable (Bool) async -> Void)? = nil,
        sequentialDelay: Duration = Constants.multiPasteSequentialDelay
    ) {
        self.sequentialDelay = sequentialDelay
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
        // ack 대기 → synthesizeCommandV 지연 함정 fix. 실패 시 해제 보장은 `withPastePending` 이 맡는다.
        try await withPastePending {
            try writeToPasteboard(clip: clip)

            // TASK-023 회귀 (e) fix — pasteboard 박은 직후 watcher 에 통보. synthesizer ⌘V 합성은 *읽기* 동작이라 추가 changeCount 증가 X, 콜백은 합성 전 호출 안전.
            await onPasteboardWritten?()

            if mode == .autoPaste {
                try synthesizer.synthesizeCommandV()
            }

            try await repository.updateLastUsedAt(id: clip.id)
            Logger.paste.info("Paste done: type=\(clip.type.rawValue, privacy: .public), mode=\(mode.rawValue, privacy: .public)")
        }
    }

    // MARK: - 묶음 붙여넣기 (TASK-099)

    /// 텍스트 묶음 — 연결자로 이어붙인 **단일 문자열** 하나를 기록한다.
    /// 단일 클립 경로와 달리 `updateLastUsedAt` 을 부르지 않는다 — 붙인 것은 *선택한 클립들* 이 아니라
    /// 그것들을 이어붙인 새 산출물이고, 그 산출물은 호출자가 새 클립으로 등록한다(등록 자체가 최신 항목이 된다).
    func pasteJoinedText(_ text: String, mode: PasteMode) async throws {
        Logger.paste.info("MultiPaste 텍스트 묶음 — mode=\(mode.rawValue, privacy: .public) 길이=\(text.count, privacy: .public)")
        try await withPastePending {
            await writeText(text)
            if mode == .autoPaste {
                try synthesizer.synthesizeCommandV()
            }
        }
    }

    /// 파일 묶음 — 파일 URL 배열을 한 번에 기록한다 (다중 파일 클립 붙여넣기와 같은 경로).
    func pasteFileURLs(_ urls: [URL], mode: PasteMode) async throws {
        guard !urls.isEmpty else {
            Logger.paste.error("MultiPaste 파일 묶음 실패 — URL 0건")
            throw PasteError.fileURLLoadFailed
        }
        Logger.paste.info("MultiPaste 파일 묶음 — mode=\(mode.rawValue, privacy: .public) 개수=\(urls.count, privacy: .public)")
        try await withPastePending {
            await writeFiles(urls)
            if mode == .autoPaste {
                try synthesizer.synthesizeCommandV()
            }
        }
    }

    /// 혼합 묶음 — **계열별로 모아 두 번** 붙인다. 파일·이미지 배열이 먼저, 이어서 연결된 텍스트.
    ///
    /// 페이스트보드는 *순서 개념 없는 단일 상태* 라 텍스트와 파일을 한 번의 붙여넣기로 표현할 수 없다.
    /// 그래서 이 경로만 **자동 붙여넣기를 전제로** 한다 (합성 없이는 순서 자체가 성립하지 않는다).
    ///
    /// 처음에는 선택 순서대로 항목마다 합성했는데, 계열이 번갈아 나오면 합성이 항목 수만큼 늘어나고
    /// 매번 붙는 앱이 앞 항목을 처리했기를 기대해야 해서 뒤쪽이 누락됐다(사용자 검수: `이미지 → 텍스트 → 이미지`
    /// 에서 마지막 이미지 실패). 계열별로 모으면 합성이 **2회로 고정** 돼 실패 지점 자체가 줄어든다.
    /// 두 묶음 사이 지연은 여전히 필요하다 — 앞 붙여넣기를 앱이 처리하기 전에 클립보드를 덮어쓰면 안 된다.
    func pasteMixed(fileURLs: [URL], joinedText: String?) async throws {
        let hasFiles = !fileURLs.isEmpty
        let hasText = !(joinedText ?? "").isEmpty
        guard hasFiles || hasText else { return }
        Logger.paste.info("MultiPaste 혼합 시작 — 파일=\(fileURLs.count, privacy: .public) 텍스트=\(hasText, privacy: .public) 지연=\(String(describing: self.sequentialDelay), privacy: .public)")
        try await withPastePending {
            if hasFiles {
                await writeFiles(fileURLs)
                try synthesizer.synthesizeCommandV()
                Logger.paste.info("MultiPaste 혼합 1/2 — 파일 \(fileURLs.count, privacy: .public)건 붙여넣기")
                // 텍스트가 뒤따를 때만 기다린다 (마지막 붙여넣기 뒤에는 기다릴 이유가 없다).
                if hasText {
                    try? await Task.sleep(for: sequentialDelay)
                }
            }
            if hasText, let text = joinedText {
                await writeText(text)
                try synthesizer.synthesizeCommandV()
                Logger.paste.info("MultiPaste 혼합 2/2 — 텍스트 \(text.count, privacy: .public)자 붙여넣기")
            }
        }
        Logger.paste.info("MultiPaste 혼합 완료")
    }

    /// 페이스트보드에 텍스트를 기록하고 watcher 에 통보한다.
    /// 통보를 쓰기와 한 몸으로 묶어 두는 이유는 **빠뜨리면 stash 가 자기 쓰기를 새 복사로 다시 수집** 하기 때문이다.
    private func writeText(_ text: String) async {
        pasteboard.clearAndDeclareTypes([.string])
        pasteboard.setString(text, forType: .string)
        await onPasteboardWritten?()
    }

    /// 파일 URL 배열 기록 + watcher 통보. `writeText` 와 같은 사유로 한 몸이다.
    private func writeFiles(_ urls: [URL]) async {
        pasteboard.writeFileURLs(urls)
        await onPasteboardWritten?()
    }

    /// 페이스트보드를 건드리는 동안 watcher tick 을 멈춘다 (TASK-026 의 `setPastePending` 과 같은 사유).
    /// 실패해도 pending 이 반드시 풀리도록 묶어 둔다 — 풀리지 않으면 이후 복사가 통째로 수집되지 않는다.
    private func withPastePending(_ work: () async throws -> Void) async rethrows {
        await setPastePending?(true)
        do {
            try await work()
            await setPastePending?(false)
        } catch {
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
