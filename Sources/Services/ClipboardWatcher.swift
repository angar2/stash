// 클립보드 변경을 500ms 폴링으로 감지하는 actor (TASK-033 *저장하지 않을 앱* 매칭 + TASK-040 클립 출처 박음)
import Foundation
import AppKit
import OSLog

actor ClipboardWatcher {
    private let pasteboard: Pasteboard
    private let fileClipService: FileClipService
    private let repository: ClipRepository
    /// TASK-026 — 다중 파일 임계 초과 / 부분 실패 시 사용자 인지용 메시지 dispatch.
    /// Composition Root가 `{ msg in await MainActor.run { toastQueue.enqueue(.warn, msg) } }` 박음.
    private let onUserMessage: (@Sendable (String) async -> Void)?
    /// TASK-033 — *저장하지 않을 앱* 매칭 + TASK-040 클립 출처 박음 백엔드. frontmost 앱 번들 ID 노출. nil 가능 (테스트 환경 등).
    private let frontmostTracker: FrontmostAppTracking?

    private var lastChangeCount: Int = -1
    private var pollingTask: Task<Void, Never>?
    /// TASK-026 fix — paste 진행 중에는 tick 자체 skip. 다중 파일 paste의 saveFiles 시간 소요로 인한
    /// *acknowledgeOwnWrite 대기 → synthesizeCommandV 지연* race 차단. PasteService 가 begin/end 호출.
    private var pastePending: Bool = false

    init(
        pasteboard: Pasteboard = SystemPasteboard.shared,
        fileClipService: FileClipService,
        repository: ClipRepository,
        onUserMessage: (@Sendable (String) async -> Void)? = nil,
        frontmostTracker: FrontmostAppTracking? = nil
    ) {
        self.pasteboard = pasteboard
        self.fileClipService = fileClipService
        self.repository = repository
        self.onUserMessage = onUserMessage
        self.frontmostTracker = frontmostTracker
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Constants.clipboardPollingInterval)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// PasteService 가 자기 자신이 pasteboard 박은 직후 호출 — `lastChangeCount` 를 *지금 막 박은 값* 으로 동기화해 다음 tick에서 idle 처리.
    /// 일반 클립보드 매니저 표준 self-write skip 패턴 (TASK-023 사용자 검수 회귀 (e) fix).
    func acknowledgeOwnWrite() {
        lastChangeCount = pasteboard.changeCount
        Logger.clipboard.info("ClipboardWatcher: own-write acknowledged (lastChangeCount=\(self.lastChangeCount))")
    }

    /// TASK-026 fix — paste 진행 시작/종료 시 PasteService 가 호출. 다중 파일 paste의 saveFiles race 차단.
    /// `true` 시 tick 자체 skip → ack 대기 시간 0 → synthesizeCommandV 즉시 진행.
    func setPastePending(_ pending: Bool) {
        pastePending = pending
        Logger.clipboard.info("ClipboardWatcher: pastePending=\(pending)")
    }

    func tick() async {
        guard !pastePending else {
            // TASK-026 fix — paste 진행 중 tick race 차단.
            return
        }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        do {
            guard let clip = try await buildClip(from: pasteboard) else { return }
            let deletedByLRU = try await repository.insert(clip)
            for deleted in deletedByLRU {
                try? await fileClipService.delete(deleted)
            }
        } catch {
            Logger.clipboard.error("ClipboardWatcher tick failed: \(error)")
        }
    }

    private func buildClip(from pasteboard: Pasteboard) async throws -> Clip? {
        // TASK-033 — *저장하지 않을 앱* 매칭 + TASK-040 클립 출처 박음. frontmost 앱 번들 ID 한 번 추출.
        let frontmostBundle = await frontmostTracker?.currentBundleId
        if let frontmostBundle {
            let blockedIds = UserDefaults.standard.stringArray(forKey: "blockedAppBundleIds") ?? []
            if blockedIds.contains(frontmostBundle) {
                Logger.clipboard.info("buildClip: blocked app — frontmost=\(frontmostBundle, privacy: .public) skip")
                return nil
            }
        }

        // TransientType / ConcealedType 감지 — 비밀번호 관리자 등이 exclude 마킹한 클립 (nspasteboard.org 컨벤션 정합).
        // TASK-033 — ConcealedType 신규 추가 (일부 비밀번호 매니저가 ConcealedType 만 박는 케이스 대응).
        let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pasteboard.availableType(from: [transientType, concealedType]) == nil else {
            Logger.clipboard.debug("buildClip: transient/concealed type detected — skip")
            return nil
        }

        let now = Date()
        let id = UUID()

        // ⓐ 파일 URL 분기 — TASK-026 다중 파일 통합 진입점.
        // `readFileURLs()` 단일 호출로 N=0/1/many 분기. 기존 `string(forType: .fileURL)` 단건 호출 폐기.
        if let urls = pasteboard.readFileURLs(), !urls.isEmpty {
            // 임계 N > 100 → 토스트 + SKIP
            if urls.count > Constants.maxMultiFileEntries {
                Logger.clipboard.info("buildClip: multi-file limit exceeded — count=\(urls.count) skipped")
                await onUserMessage?(String(localized: "toast.multiFileLimitExceeded"))
                return nil
            }
            // N=1 → 기존 단일 파일 분기 (확장자 화이트리스트로 .image / .file 판별, case C/D 정합).
            if urls.count == 1 {
                let url = urls[0]
                let ext = url.pathExtension.lowercased()
                let isImage = Constants.imageFileExtensions.contains(ext)
                let clipType: ClipType = isImage ? .image : .file
                Logger.clipboard.info("buildClip: file URL detected — ext=\(ext, privacy: .public) → type=\(String(describing: clipType), privacy: .public)")
                let stored = try await fileClipService.saveFile(at: url)
                return Clip(
                    id: id, type: clipType, body: nil,
                    filePath: stored.filePath.path, isFileExternal: stored.isFileExternal,
                    fileOriginalPath: url.path, fileBookmark: nil,
                    sourceAppBundleId: frontmostBundle, isPinned: false,
                    createdAt: now, lastUsedAt: now
                )
            }
            // N>1 → 다중 파일 묶음 분기 (case F). 별도 helper 위임 (buildClip SRP).
            return try await buildMultiFileClip(from: urls, now: now, id: id, sourceAppBundleId: frontmostBundle)
        }

        // ⓑ 메모리 비트맵 — file URL 없이 .tiff/.png 데이터만 있는 케이스 (스크린샷 / 브라우저 이미지 우클릭 복사).
        // DATA-MODEL §case B — `fileOriginalPath = NULL`.
        // TASK-023 회귀 (g) — 브라우저(Safari/Chrome 등)는 웹 이미지 ⌘C 시 `public.url` 타입에 *원본 web URL* 동시 박음. body 에 박아 클립 라벨 표시 (스크린샷처럼 URL 없으면 nil — fallback "이미지").
        if let imageType = pasteboard.availableType(from: [.tiff, .png]),
           let data = pasteboard.data(forType: imageType) {
            let sourceURL = pasteboard.string(forType: .URL)
            if let sourceURL {
                Logger.clipboard.info("buildClip: web image with source URL: \(sourceURL, privacy: .public)")
            } else {
                Logger.clipboard.info("buildClip: pasteboard image data → .image (no file URL, no source URL)")
            }
            let stored = try await fileClipService.saveData(data, type: .image)
            return Clip(
                id: id, type: .image, body: sourceURL,
                filePath: stored.filePath.path, isFileExternal: stored.isFileExternal,
                fileOriginalPath: nil, fileBookmark: nil,
                sourceAppBundleId: frontmostBundle, isPinned: false,
                createdAt: now, lastUsedAt: now
            )
        }

        // ⓒ 텍스트 — 가장 일반적, 마지막 fallback
        if let text = pasteboard.string(forType: .string) {
            return Clip(
                id: id, type: .text, body: text,
                filePath: nil, isFileExternal: false,
                fileOriginalPath: nil, fileBookmark: nil,
                sourceAppBundleId: frontmostBundle, isPinned: false,
                createdAt: now, lastUsedAt: now
            )
        }

        return nil
    }

    /// TASK-026 — 다중 파일 묶음 (N>1) 캡쳐 분기. 옵션 A — 어느 하나라도 실패 시 전체 SKIP + 토스트 + 카피본 cleanup (saveFiles 내부 처리).
    private func buildMultiFileClip(from urls: [URL], now: Date, id: UUID, sourceAppBundleId: String?) async throws -> Clip? {
        Logger.clipboard.info("buildClip: multi-file detected — count=\(urls.count)")
        do {
            let stored = try await fileClipService.saveFiles(at: urls)
            let entries = zip(urls, stored).map { (originalURL, sf) in
                ClipFileEntry(
                    originalPath: originalURL.path,
                    filePath: sf.filePath.path,
                    isFileExternal: sf.isFileExternal
                )
            }
            let json = try ClipFileEntry.encodeJSON(entries)
            return Clip(
                id: id, type: .file, body: nil,
                filePath: nil, isFileExternal: false,
                fileOriginalPath: nil, fileBookmark: nil,
                sourceAppBundleId: sourceAppBundleId, isPinned: false,
                createdAt: now, lastUsedAt: now,
                pinnedAt: nil, filePathsJson: json
            )
        } catch {
            // saveFiles 가 이미 *부분 카피본 cleanup* 수행 — 본 catch 는 토스트 + SKIP 만.
            Logger.clipboard.error("buildClip: multi-file save failed — \(error)")
            await onUserMessage?(String(localized: "toast.multiFileSaveFailed"))
            return nil
        }
    }
}
