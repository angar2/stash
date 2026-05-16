// 1·2·3 popover 공통 클립 리스트 + 검색 + paste/pop/pin/delete 액션 ViewModel (API-SPEC §9-2 ViewModel 예외 룰 정합)
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
    var pinSidebarOpen: Bool = false {    // Pin 사이드 펼침 여부
        didSet {
            // TASK-019 — `PopoverWindow`가 별도 NSPanel 호스팅 토글. @Observable stored property 의 didSet 정상 동작.
            if oldValue != pinSidebarOpen {
                onPinSidebarOpenChange?(pinSidebarOpen)
            }
        }
    }
    /// `pinSidebarOpen` 변경 시 호출 — `PopoverWindow`가 init에서 등록해 별도 NSPanel show/hide.
    var onPinSidebarOpenChange: (@MainActor (Bool) -> Void)?
    /// `pinnedClips` count 변화 시 호출 — Pin 사이드바 panel size 재조정 (사이드바 열려있는 경우).
    var onPinnedClipsChange: (@MainActor () -> Void)?
    var pinHoverActive: Bool = false      // Pin 행 hover 상태
    var pinSelectedIdx: Int = 0           // Pin 사이드바 안 선택 idx
    /// 키보드 nav 시 set — ScrollView가 `proxy.scrollTo(id)` (anchor:nil) 로 *id 가 가시 안이면 무동작, 밖이면 가장 가까운 위치로 자동 스크롤* (TASK-019 fix 6차).
    var pendingScrollToId: UUID? = nil
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

    /// popover 본문 — 일반 히스토리에 *Pin 항목도 시간순 자연 노출* (FEATURES §3-4 / F-004 정합, TASK-019 fix).
    /// 이전 코드: `filteredClips.filter { !$0.isPinned }` — plan과 어긋난 버그. 핀 토글 시 일반 목록에서 사라짐 문제 발생.
    /// 현재: 모든 클립 노출. 핀 시각 구분은 `ClipRowView`가 `clip.isPinned` 분기로 자동 (행 우측 파란 압정 아이콘).
    var visibleClips: [Clip] {
        filteredClips
    }

    /// Pin 사이드바 — 핀 항목 별도 보장 노출 채널 (일반 히스토리 외 추가 채널).
    /// TASK-019 — 정렬 = `pinned_at DESC` (최근 핀이 상단). NULL fallback = `created_at` (V3 마이그레이션 이전 핀 row 안전망 — 마이그레이션이 last_used_at 으로 초기화하므로 일반 케이스 nil X).
    var pinnedClips: [Clip] {
        clips.filter { $0.isPinned }.sorted { lhs, rhs in
            (lhs.pinnedAt ?? lhs.createdAt) > (rhs.pinnedAt ?? rhs.createdAt)
        }
    }

    /// 일반 히스토리 영역이 비어 있는 상태 — 검색어 없고 모든 클립(핀 포함) 0건.
    /// TASK-019 이후: 핀이 일반 히스토리에 포함 노출되므로 핀만 있을 때 isEmptyState=false (자연스러움).
    var isEmptyState: Bool {
        visibleClips.isEmpty && searchQuery.isEmpty
    }

    /// `focusZone` 기반 현재 활성 idx — `.pin` 이면 `pinSelectedIdx`, 그 외는 `selectedIdx`.
    /// dispatch site 의 반복 패턴 (`focusZone == .pin ? pinSelectedIdx : selectedIdx`) 정리 (TASK-019 리팩토링).
    var activeIdx: Int {
        focusZone == .pin ? pinSelectedIdx : selectedIdx
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
    /// TASK-019 — anchor:nil 스크롤 모델. SwiftUI `scrollTo(id)` 의 anchor 기본 nil — id 가 가시 안이면 변화 X, 밖이면 가장 가까운 가시 위치로 자동 스크롤. multiline 행 가변 height 무관.
    /// focusZone == .pin 분기는 별도 (사이드바 안 pinSelectedIdx wrap).
    func moveSelectionDown() {
        if focusZone == .pin {
            let count = pinnedClips.count
            guard count > 0 else { return }
            pinSelectedIdx = (pinSelectedIdx + 1) % count
            return
        }

        let list = visibleClips
        let count = list.count
        guard count > 0 else { return }
        focusZone = .clip
        selectedIdx = (selectedIdx + 1) % count
        pendingScrollToId = list[selectedIdx].id
    }

    func moveSelectionUp() {
        if focusZone == .pin {
            let count = pinnedClips.count
            guard count > 0 else { return }
            pinSelectedIdx = (pinSelectedIdx - 1 + count) % count
            return
        }

        let list = visibleClips
        let count = list.count
        guard count > 0 else { return }
        focusZone = .clip
        selectedIdx = (selectedIdx - 1 + count) % count
        pendingScrollToId = list[selectedIdx].id
    }

    /// Pin 사이드바 안 hover — pinSelectedIdx 갱신 (TASK-019 fix 2차).
    func setPinSelectedIdx(_ idx: Int) {
        if isHoverIgnored { return }
        guard idx >= 0 && idx < pinnedClips.count else { return }
        focusZone = .pin
        pinSelectedIdx = idx
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
        searchInputActive = false
        searchQuery = ""
        pinSidebarOpen = false
        pinHoverActive = false
        pendingScrollToId = nil
        ignoreHoverUntil = Date().addingTimeInterval(DesignTokens.Animation.popoverOpenHoverIgnoreDelay)
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
    /// TASK-019 fix 2차 — focusZone == .pin 일 때 *pinnedClips 안 항목* paste. 본체 visibleClips 는 focusZone == .clip 일 때만.
    func paste(at idx: Int) async {
        let clip: Clip
        if focusZone == .pin {
            guard idx >= 0 && idx < pinnedClips.count else { return }
            clip = pinnedClips[idx]
        } else {
            let list = visibleClips
            guard idx >= 0 && idx < list.count else { return }
            clip = list[idx]
        }
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
        let clip: Clip
        if focusZone == .pin {
            guard idx >= 0 && idx < pinnedClips.count else { return }
            clip = pinnedClips[idx]
        } else {
            let list = visibleClips
            guard idx >= 0 && idx < list.count else { return }
            clip = list[idx]
        }
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

    /// TASK-019 fix 2차 — 본체 클립 선택 상태에서 토글. 정렬 변동(is_pinned DESC)으로 같은 클립이 다른 idx로 이동하므로 토글 후 `selectedIdx`를 같은 id의 새 idx로 갱신 (B1 fix).
    func togglePin(at idx: Int) async {
        let list = visibleClips
        guard idx >= 0 && idx < list.count else { return }
        let clip = list[idx]
        await togglePin(id: clip.id, trackSelection: .clip)
    }

    /// TASK-019 fix 2차 — Pin 사이드바 안 항목의 핀해제 (id 기반 호출). Pin 사이드바 안 ⌘P / 핀해제 버튼 클릭 / ⌘⌫ 모두 동일 호출.
    /// TASK-019 fix 4차 — 정렬 룰에서 `is_pinned DESC` 제거 → 토글 후 행 위치 변동 X.
    /// TASK-019 fix 5차 — B7 (동일 body 핀 차단) 정책 제거. dedup 은 `GRDBClipRepository.performInsert` 의 *insert 시점 dedup* 으로 이관 (`paste 후 자동 감지로 누적된 동일 body 클립* 자체 차단). B7 차단은 사용자 선택 행 핀이 막히는 함정이라 제거.
    func togglePin(id: UUID, trackSelection: FocusZone = .clip) async {
        do {
            try await repository.togglePin(id: id)
            await reload()
            // .clip 분기는 정렬 룰 (`last_used_at DESC` 만) 이후 *행 위치 변동 X* — selectedIdx 추적 불필요.
            if trackSelection == .pin {
                // Pin 사이드바 안 unpin → pinnedClips count 감소. pinSelectedIdx clamp.
                let count = pinnedClips.count
                if count == 0 {
                    pinSelectedIdx = 0
                    // 마지막 핀 해제됨 → 사이드바 자동 닫음.
                    collapsePinSidebar()
                } else if pinSelectedIdx >= count {
                    pinSelectedIdx = count - 1
                }
            }
            // pinnedClips count 변화 알림 — PopoverWindow 가 사이드바 panel size 재조정.
            onPinnedClipsChange?()
        } catch DatabaseError.pinLimitReached {
            Logger.ui.warning("Pin 한도 초과 — 토스트 발행")
            toastQueue?.enqueue(.warn, String(localized: "toast.pinLimit"), ttl: DesignTokens.Animation.toastTTLDefault)
        } catch {
            Logger.ui.error("ClipsViewModel.togglePin error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// TASK-019 fix 2차 — focusZone == .pin 일 때 ⌘⌫ 는 *클립 row 삭제가 아니라 unpin* 으로 동작 (DB row 유지).
    func delete(at idx: Int) async {
        if focusZone == .pin {
            guard idx >= 0 && idx < pinnedClips.count else { return }
            let clip = pinnedClips[idx]
            await togglePin(id: clip.id, trackSelection: .pin)
            return
        }
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

    /// → 키 또는 클릭으로 즉시 펼침 (지연 X). 빈 핀 상태에서는 no-op (TASK-019).
    func expandPinSidebarImmediately() {
        guard !pinnedClips.isEmpty else { return }
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

    /// Pin Row 클릭 / `⌘B` 단축키 — 사이드바 토글 (열려있으면 닫고 / 닫혀있으면 펼침). 빈 핀 상태에서 no-op (TASK-019).
    /// 단일 진실 — FEATURES §3-7 Pin 사이드바 트리거 정리 정합.
    func togglePinSidebar() {
        if pinSidebarOpen {
            collapsePinSidebar()
        } else {
            expandPinSidebarImmediately()
        }
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
            return
        }
        if selectedIdx >= count {
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
