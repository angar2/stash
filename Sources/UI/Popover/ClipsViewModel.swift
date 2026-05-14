// 방식 1·3 popover의 클립 리스트 + 검색 + paste/pop/pin/delete 액션 ViewModel (API-SPEC §9-2 ViewModel 예외 룰 정합)
import Foundation
import Observation
import OSLog
import AppKit

@MainActor
@Observable
final class ClipsViewModel {
    // MARK: - State
    var clips: [Clip] = []
    var searchQuery: String = ""
    var focusZone: FocusZone = .clip
    var selectedIdx: Int = 0
    var searchInputActive: Bool = false  // 검색란 인풋 활성 여부 (Enter / 클릭 시 true)
    var flashedClipId: UUID?              // paste 직후 플래시 대상
    var pasteMode: PasteMode = .autoPaste
    var pinSidebarOpen: Bool = false      // Pin 사이드 펼침 여부
    var pinHoverActive: Bool = false      // Pin 행 hover 상태
    var pinSelectedIdx: Int = 0           // Pin 사이드바 안 선택 idx
    private var pinExpandTask: Task<Void, Never>?
    private var pinCloseTask: Task<Void, Never>?

    // MARK: - Dependencies
    private let repository: any ClipRepository
    private let pasteService: PasteService
    private weak var toastQueue: ToastQueue?

    init(repository: any ClipRepository, pasteService: PasteService, toastQueue: ToastQueue? = nil) {
        self.repository = repository
        self.pasteService = pasteService
        self.toastQueue = toastQueue
    }

    func setToastQueue(_ queue: ToastQueue) {
        self.toastQueue = queue
    }

    // MARK: - Derived
    var filteredClips: [Clip] {
        if searchQuery.isEmpty { return clips }
        return clips.filter {
            ($0.body ?? "").localizedCaseInsensitiveContains(searchQuery)
        }
    }

    /// popover 본문 (비핀만) — Pin 사이드바와 분리
    var visibleClips: [Clip] {
        filteredClips.filter { !$0.isPinned }
    }

    /// Pin 사이드바
    var pinnedClips: [Clip] {
        clips.filter { $0.isPinned }
    }

    var isEmptyState: Bool {
        clips.isEmpty && searchQuery.isEmpty
    }

    var isSearchEmptyResult: Bool {
        !searchQuery.isEmpty && visibleClips.isEmpty
    }

    // MARK: - Reload / Search
    func reload() async {
        do {
            let fetched = try await repository.fetchAll()
            clips = fetched
            clampSelection()
        } catch {
            Logger.ui.error("ClipsViewModel.reload error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func performSearch() async {
        do {
            let result = try await repository.search(query: searchQuery)
            clips = result
            selectedIdx = 0
        } catch {
            Logger.ui.error("ClipsViewModel.performSearch error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Navigation
    func moveSelectionDown() {
        let count = visibleClips.count
        guard count > 0 else { return }
        focusZone = .clip
        selectedIdx = (selectedIdx + 1) % count
    }

    func moveSelectionUp() {
        let count = visibleClips.count
        guard count > 0 else { return }
        focusZone = .clip
        selectedIdx = (selectedIdx - 1 + count) % count
    }

    func setSelectedIdx(_ idx: Int) {
        guard idx >= 0 && idx < visibleClips.count else { return }
        focusZone = .clip
        selectedIdx = idx
    }

    func enterSearchZone() {
        focusZone = .search
        searchInputActive = false
    }

    /// hover 시 focusZone 자동 변경 (popover.jsx L329 / L470 정합)
    func setFocusZone(_ zone: FocusZone) {
        if focusZone != zone {
            focusZone = zone
        }
    }

    func activateSearchInput() {
        focusZone = .search
        searchInputActive = true
    }

    /// ESC 1번 동작 — 인풋 해제 + 검색어 리셋 + focusZone="search" 유지
    func deactivateSearchInputAndClear() {
        searchInputActive = false
        searchQuery = ""
        focusZone = .search
    }

    // MARK: - Actions
    func paste(at idx: Int) async {
        let list = visibleClips
        guard idx >= 0 && idx < list.count else { return }
        let clip = list[idx]
        do {
            try await pasteService.paste(clip: clip, mode: pasteMode)
            triggerPasteFlash(for: clip.id)
            publishPasteToast(for: clip)
        } catch {
            Logger.ui.error("ClipsViewModel.paste error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishPasteToast(for clip: Clip) {
        guard let toastQueue else { return }
        let snippet = String((clip.body ?? "").prefix(20))
        if pasteMode == .autoPaste {
            toastQueue.enqueue(.success, String(localized: "toast.paste.done") + ": \(snippet)", ttl: DesignTokens.Animation.toastTTLShort)
        } else {
            toastQueue.enqueue(.info, String(localized: "toast.copyBack.done"), ttl: DesignTokens.Animation.toastTTLDefault)
        }
    }

    func pop(at idx: Int) async {
        let list = visibleClips
        guard idx >= 0 && idx < list.count else { return }
        let clip = list[idx]
        do {
            try await pasteService.paste(clip: clip, mode: pasteMode)
            if !clip.isPinned {
                _ = try? await repository.delete(id: clip.id)
                await reload()
            } else {
                Logger.ui.info("Pop on pinned clip — silent fallback to paste only")
            }
            triggerPasteFlash(for: clip.id)
        } catch {
            Logger.ui.error("ClipsViewModel.pop error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func togglePin(at idx: Int) async {
        let list = visibleClips
        guard idx >= 0 && idx < list.count else { return }
        let clip = list[idx]
        do {
            try await repository.togglePin(id: clip.id)
            await reload()
        } catch DatabaseError.pinLimitReached {
            Logger.ui.warning("Pin 한도 초과 — 토스트 발행")
            toastQueue?.enqueue(.warn, String(localized: "toast.pinLimit"), ttl: DesignTokens.Animation.toastTTLDefault)
        } catch {
            Logger.ui.error("ClipsViewModel.togglePin error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(at idx: Int) async {
        let list = visibleClips
        guard idx >= 0 && idx < list.count else { return }
        let clip = list[idx]
        _ = try? await repository.delete(id: clip.id)
        await reload()
        clampSelection()
    }

    func deleteAllExceptPinned() async {
        _ = try? await repository.deleteAllExceptPinned()
        await reload()
        selectedIdx = 0
        toastQueue?.enqueue(.info, String(localized: "toast.deleteAll.done"), ttl: DesignTokens.Animation.toastTTLLong)
    }

    // MARK: - Pin sidebar
    /// Pin 행 hover 진입 — 200ms 후 사이드 펼침
    func pinRowHoverEnter() {
        pinHoverActive = true
        pinCloseTask?.cancel()
        pinCloseTask = nil
        pinExpandTask?.cancel()
        pinExpandTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.Animation.pinSidebarHoverOpenDelay * 1_000_000_000))
            if !Task.isCancelled && pinHoverActive {
                pinSidebarOpen = true
            }
        }
    }

    /// Pin 행 hover 이탈 — 사이드 hover 상태 검사 후 200ms 지연 닫힘
    func pinRowHoverExit() {
        pinHoverActive = false
        pinExpandTask?.cancel()
        scheduleSidebarCloseIfNeeded()
    }

    /// Pin 사이드 자체 hover 진입 — close 타이머 취소
    func pinSidebarHoverEnter() {
        pinHoverActive = true
        pinCloseTask?.cancel()
        pinCloseTask = nil
    }

    /// Pin 사이드 hover 이탈 — 200ms 지연 닫힘
    func pinSidebarHoverExit() {
        pinHoverActive = false
        scheduleSidebarCloseIfNeeded()
    }

    /// → 키로 즉시 펼침 (지연 X)
    func expandPinSidebarImmediately() {
        pinExpandTask?.cancel()
        pinSidebarOpen = true
        focusZone = .pin
    }

    /// ← / ESC — 사이드 닫음 + focusZone="clip" 복귀
    func collapsePinSidebar() {
        pinExpandTask?.cancel()
        pinCloseTask?.cancel()
        pinSidebarOpen = false
        focusZone = .clip
    }

    private func scheduleSidebarCloseIfNeeded() {
        pinCloseTask?.cancel()
        pinCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.Animation.pinSidebarHoverOpenDelay * 1_000_000_000))
            if !Task.isCancelled && !pinHoverActive {
                pinSidebarOpen = false
            }
        }
    }

    // MARK: - Private helpers
    private func clampSelection() {
        let count = visibleClips.count
        if count == 0 {
            selectedIdx = 0
        } else if selectedIdx >= count {
            selectedIdx = count - 1
        }
    }

    private func triggerPasteFlash(for id: UUID) {
        flashedClipId = id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.Animation.pasteFlashDuration * 1_000_000_000))
            if flashedClipId == id { flashedClipId = nil }
        }
    }
}
