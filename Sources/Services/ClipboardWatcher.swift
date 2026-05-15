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

        // ⓐ 이미지 (.tiff / .png) 우선 — Finder에서 *이미지 파일* 복사 시에도 .tiff/.png 데이터가 박힘. file URL보다 우선해 .image로 분류 (TASK-016 Bug 5 D-7/D-8 폴더 아이콘 통일 문제 fix v3).
        if let imageType = pasteboard.availableType(from: [.tiff, .png]),
           let data = pasteboard.data(forType: imageType) {
            let stored = try await fileClipService.saveData(data, type: .image)
            return Clip(
                id: id, type: .image, body: nil,
                filePath: stored.filePath.path, isFileExternal: stored.isFileExternal,
                fileOriginalPath: nil, fileBookmark: nil,
                sourceAppBundleId: nil, isPinned: false,
                createdAt: now, lastUsedAt: now
            )
        }

        // ⓑ 파일 URL — 이미지 데이터가 없는 일반 파일/폴더. 폴더 / 파일 분기는 ClipRowView가 FileManager isDirectory로 분기 (DB 모델 변경 X).
        let fileURLType = NSPasteboard.PasteboardType("public.file-url")
        if let urlString = pasteboard.string(forType: fileURLType),
           let url = URL(string: urlString) {
            let stored = try await fileClipService.saveFile(at: url)
            return Clip(
                id: id, type: .file, body: nil,
                filePath: stored.filePath.path, isFileExternal: stored.isFileExternal,
                fileOriginalPath: url.path, fileBookmark: nil,
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
