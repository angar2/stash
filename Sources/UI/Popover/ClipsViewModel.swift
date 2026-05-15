// 1·2·3 popover 공통 클립 리스트 + 검색 + paste/pop/pin/delete 액션 ViewModel (API-SPEC §9-2 ViewModel 예외 룰 정합)
import Foundation
import Observation
import OSLog
import AppKit

/// 키보드 네비 시 ScrollView 페이징 anchor 힌트 (TASK-018 Phase 3) — SwiftUI UnitPoint 의존 X (ViewModel 순수성 유지).
enum ScrollAnchorHint {
    case top
    case bottom
}

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
    /// 키보드 nav (↑↓·1·2)로 가시 영역 *경계 진출* 시에만 set — ScrollView가 anchor 위치로 1행 시프트 (TASK-018 Phase 3, 행 단위 페이징 모델).
    /// 가시 영역 안 커서 이동 / hover 변경은 nil 유지 → 가시 영역 안 스크롤 발생 차단.
    var pendingScrollToId: UUID? = nil
    /// pendingScrollToId 동반 — ScrollView가 어느 anchor 위치로 옮길지. top = top index 시프트 / bottom = wrap 시 마지막 행을 하단으로.
    var pendingScrollAnchor: ScrollAnchorHint = .top
    /// 키보드 네비 가시 윈도우의 top idx — 화면 최상단에 보이는 clip의 visibleClips 안 index. 키보드 nav가 가시 영역 *밖*으로 selectedIdx 시프트 시에만 ±1 갱신.
    var visibleTopIdx: Int = 0
    /// 가시 행 수 — `clipListMaxHeight(312) ÷ (rowMinHeight 44 + rowGap 2) ≒ 6` (single-line 기준).
    /// multi-line 행이 섞이면 실제 화면 가시는 더 적을 수 있으나, 시프트 동작은 본 상한으로 정확. 마우스 휠 스크롤은 추적 X — 다음 키 입력 시 ScrollView가 visibleTopIdx 기준 재동기화.
    private let visibleRowCount: Int = 6
    private var pinExpandTask: Task<Void, Never>?
    private var pinCloseTask: Task<Void, Never>?
    /// popover 열림 직후 짧은 시간 동안 hover (setFocusZone) 무시 — 마우스가 검색바/클립 위에 이미 있어도 자동 활성 차단.
    private var ignoreHoverUntil: Date = .distantPast

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

    /// 일반 히스토리 영역이 비어 있는 상태 — 검색어 없고 unpinned 0건. Pin 있더라도 빈 상태 안내 노출 (TASK-018 Phase 5).
    /// Pin 메뉴란은 `hasPinned` 분기로 별도 유지 (FEATURES.md §빈 상태 표시 적용 범위 정합).
    var isEmptyState: Bool {
        visibleClips.isEmpty && searchQuery.isEmpty
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

    // MARK: - Navigation (행 단위 페이징 — TASK-018 Phase 3)
    func moveSelectionDown() {
        let list = visibleClips
        let count = list.count
        guard count > 0 else { return }
        focusZone = .clip

        let prev = selectedIdx
        selectedIdx = (prev + 1) % count

        // wrap (count-1 → 0) — 리스트 끝에서 처음으로 돌아감
        if prev == count - 1 && selectedIdx == 0 {
            visibleTopIdx = 0
            pendingScrollAnchor = .top
            pendingScrollToId = list[0].id
            return
        }

        // 가시 영역 마지막 행 진출 → 정확히 1행 시프트
        let lastVisible = visibleTopIdx + visibleRowCount - 1
        if selectedIdx > lastVisible {
            visibleTopIdx = selectedIdx - visibleRowCount + 1
            pendingScrollAnchor = .top
            pendingScrollToId = list[visibleTopIdx].id
            return
        }

        // 가시 영역 안 — 스크롤 발생 X (커서만 이동)
        pendingScrollToId = nil
    }

    func moveSelectionUp() {
        let list = visibleClips
        let count = list.count
        guard count > 0 else { return }
        focusZone = .clip

        let prev = selectedIdx
        selectedIdx = (prev - 1 + count) % count

        // wrap (0 → count-1) — 리스트 처음에서 끝으로 돌아감
        if prev == 0 && selectedIdx == count - 1 {
            visibleTopIdx = max(0, count - visibleRowCount)
            pendingScrollAnchor = .bottom
            pendingScrollToId = list[count - 1].id
            return
        }

        // 가시 영역 첫 행 진출 → 정확히 1행 시프트
        if selectedIdx < visibleTopIdx {
            visibleTopIdx = selectedIdx
            pendingScrollAnchor = .top
            pendingScrollToId = list[visibleTopIdx].id
            return
        }

        // 가시 영역 안 — 스크롤 발생 X
        pendingScrollToId = nil
    }

    /// hover 시 호출 — selectedIdx만 갱신, pendingScrollToId 미설정 (스크롤 루프 차단).
    /// 검색 input 활성화 단계 2 (cursor)는 hover로 해제 X — click 트리거에서만 해제 (지크 요구).
    /// popover 열림 직후 200ms 동안 hover 무시 (자동 활성 차단).
    func setSelectedIdx(_ idx: Int) {
        if isHoverIgnored { return }
        guard idx >= 0 && idx < visibleClips.count else { return }
        focusZone = .clip
        selectedIdx = idx
    }

    /// popover 열림 직후 ignoreHoverUntil 시점 전에는 true — hover 자동 활성 차단.
    private var isHoverIgnored: Bool {
        Date() < ignoreHoverUntil
    }

    /// HistoryPopover ScrollView가 follow 완료 후 호출 — 다음 키보드 nav까지 nil 유지.
    func consumePendingScroll() {
        pendingScrollToId = nil
    }

    func enterSearchZone() {
        focusZone = .search
        searchInputActive = false
    }

    /// hover 시 focusZone 자동 변경 (popover.jsx L329 / L470 정합).
    /// 검색 input 활성화 단계 2 (cursor)는 hover로 해제 X — *click* 트리거에서만 해제 (지크 요구).
    /// popover 열림 직후 200ms는 hover 무시 — 마우스가 검색바 위에 미리 있어도 비활성 상태 유지.
    func setFocusZone(_ zone: FocusZone) {
        if isHoverIgnored { return }
        if focusZone != zone {
            focusZone = zone
        }
    }

    func activateSearchInput() {
        focusZone = .search
        searchInputActive = true
    }

    /// popover 열림 시 호출 — 초기 상태 reset (focusZone=.clip + selectedIdx=0 + searchInputActive=false + searchQuery 비움).
    /// 사용자가 popover 열 때마다 가장 최신 클립이 선택 커서로 활성된 상태.
    /// 마우스가 검색바 위에 이미 있어도 200ms 동안 hover 무시 — 자동 활성 차단.
    func resetForOpen() {
        focusZone = .clip
        selectedIdx = 0
        visibleTopIdx = 0
        searchInputActive = false
        searchQuery = ""
        pinSidebarOpen = false
        pinHoverActive = false
        pendingScrollToId = nil
        pendingScrollAnchor = .top
        ignoreHoverUntil = Date().addingTimeInterval(0.2)
    }

    /// 외부 클릭 등으로 TextField focus를 잃었을 때 호출 — searchInputActive만 해제 (검색어 / focusZone 보존).
    /// `deactivateSearchInputAndClear()`와 분리 — 본 메서드는 검색어 보존이 핵심.
    func deactivateSearchInput() {
        if searchInputActive {
            searchInputActive = false
        }
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
            visibleTopIdx = 0
            return
        }
        if selectedIdx >= count {
            selectedIdx = count - 1
        }
        if visibleTopIdx > selectedIdx {
            visibleTopIdx = selectedIdx
        }
        if visibleTopIdx + visibleRowCount > count {
            visibleTopIdx = max(0, count - visibleRowCount)
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
