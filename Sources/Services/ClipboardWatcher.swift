// 클립보드 변경을 500ms 폴링으로 감지하는 actor
import Foundation
import AppKit
import OSLog

actor ClipboardWatcher {
    private let pasteboard: Pasteboard
    private let fileClipService: FileClipService
    private let repository: ClipRepository

    private var lastChangeCount: Int = -1
    private var pollingTask: Task<Void, Never>?

    init(
        pasteboard: Pasteboard = SystemPasteboard.shared,
        fileClipService: FileClipService,
        repository: ClipRepository
    ) {
        self.pasteboard = pasteboard
        self.fileClipService = fileClipService
        self.repository = repository
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

    func tick() async {
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
        // TransientType 감지 — 비밀번호 관리자 등이 exclude 마킹한 클립
        let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        guard pasteboard.availableType(from: [transientType]) == nil else { return nil }

        let now = Date()
        let id = UUID()

        // ⓐ 파일 URL 우선 — file URL은 *명시적 출처 정보*. Finder ⌘C 시 Quick Look 썸네일이 .tiff에 박혀도 file URL이 진실값.
        // 확장자가 이미지면 .image 클립 (DATA-MODEL §case C — `Finder 작은 파일·이미지 → file / image`).
        // 그 외 확장자(txt/pdf/문서/폴더 등)는 .file 클립. (c) txt 오분류 회귀 차단의 핵심 (TASK-023).
        if let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString) {
            let ext = url.pathExtension.lowercased()
            let isImage = Constants.imageFileExtensions.contains(ext)
            let clipType: ClipType = isImage ? .image : .file
            Logger.clipboard.info("buildClip: file URL detected — ext=\(ext, privacy: .public) → type=\(String(describing: clipType), privacy: .public)")
            let stored = try await fileClipService.saveFile(at: url)
            return Clip(
                id: id, type: clipType, body: nil,
                filePath: stored.filePath.path, isFileExternal: stored.isFileExternal,
                fileOriginalPath: url.path, fileBookmark: nil,
                sourceAppBundleId: nil, isPinned: false,
                createdAt: now, lastUsedAt: now
            )
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
                sourceAppBundleId: nil, isPinned: false,
                createdAt: now, lastUsedAt: now
            )
        }

        // ⓒ 텍스트 — 가장 일반적, 마지막 fallback
        if let text = pasteboard.string(forType: .string) {
            return Clip(
                id: id, type: .text, body: text,
                filePath: nil, isFileExternal: false,
                fileOriginalPath: nil, fileBookmark: nil,
                sourceAppBundleId: nil, isPinned: false,
                createdAt: now, lastUsedAt: now
            )
        }

        return nil
    }
}
