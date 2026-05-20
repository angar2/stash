// 1·2·3 popover 공통 클립 리스트 + 검색 + paste/copy/pin/delete 액션 ViewModel (API-SPEC §9-2 ViewModel 예외 룰 정합)
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
    var focusZone: FocusZone = .clip {
        didSet {
            guard oldValue != focusZone else { return }
            // TASK-039 — zone 변경 = anchor 변경 = 이전 row frame 무효 (본체 popover ↔ PinSidebar 좌표계 불일치).
            // activeRowFrameInPopover reset (.zero) → 다음 schedule 매칭 X → 즉시 nil emit. 새 zone 행 frame 게시 시 정확 좌표 emit.
            activeRowFrameInPopover = .zero
            // `.pin && !pinSidebarOpen` (Pin 행 막 hover, PinSidebar 펼침 대기) — 즉시 nil emit + task skip. pinSidebarOpen didSet 의 schedule 가 처리.
            if focusZone == .pin && !pinSidebarOpen {
                onShowClipDetailChange?(nil)
                lastEmittedClipId = nil
                return
            }
            scheduleClipDetailUpdate()
        }
    }
    var selectedIdx: Int = 0 {
        didSet {
            // TASK-027 — selectedIdx 변경 시 detail panel 재평가.
            if oldValue != selectedIdx { scheduleClipDetailUpdate() }
        }
    }
    // TASK-025 — `searchInputActive` 폐기. 검색바 always-active 정책으로 활성 단계 개념 제거.
    var flashedClipId: UUID?              // paste 직후 플래시 대상
    /// TASK-024 — Accessibility 권한 게이트 state. `PermissionService.statusPublisher` 구독으로 Composition Root 가 갱신. 권한 X 시 ⌘V 비활성 (PopoverPanel.dispatch 게이트) + 힌트바 회색조 (KeyboardHintsView 분기).
    var accessibilityGranted: Bool = false
    var pinSidebarOpen: Bool = false {    // Pin 사이드 펼침 여부
        didSet {
            // TASK-019 — `PopoverWindow`가 별도 NSPanel 호스팅 토글. @Observable stored property 의 didSet 정상 동작.
            if oldValue != pinSidebarOpen {
                onPinSidebarOpenChange?(pinSidebarOpen)
                // TASK-039 — PinSidebar 가시 상태 변경은 detail anchor 분기 결정 변수. race 차단 위해 명시 re-schedule.
                scheduleClipDetailUpdate()
            }
        }
    }
    /// `pinSidebarOpen` 변경 시 호출 — `PopoverWindow`가 init에서 등록해 별도 NSPanel show/hide.
    var onPinSidebarOpenChange: (@MainActor (Bool) -> Void)?
    /// `pinnedClips` count 변화 시 호출 — Pin 사이드바 panel size 재조정 (사이드바 열려있는 경우).
    var onPinnedClipsChange: (@MainActor () -> Void)?
    var pinHoverActive: Bool = false      // Pin 행 hover 상태
    var pinSelectedIdx: Int = 0 {         // Pin 사이드바 안 선택 idx
        didSet {
            // TASK-027 — Pin 사이드바 안 선택 변경 시 detail panel 재평가.
            if oldValue != pinSelectedIdx { scheduleClipDetailUpdate() }
        }
    }
    /// 키보드 nav 시 set — ScrollView가 `proxy.scrollTo(id)` (anchor:nil) 로 *id 가 가시 안이면 무동작, 밖이면 가장 가까운 위치로 자동 스크롤* (TASK-019 fix 6차).
    var pendingScrollToId: UUID? = nil
    private var pinExpandTask: Task<Void, Never>?
    private var pinCloseTask: Task<Void, Never>?
    /// popover 열림 직후 짧은 시간 동안 hover (setFocusZone) 무시 — 마우스가 검색바/클립 위에 이미 있어도 자동 활성 차단.
    private var ignoreHoverUntil: Date = .distantPast

    // MARK: - Clip Detail sub-window state (TASK-027)
    /// `PopoverWindow` 가 등록 — detail panel show/hide 분기. nil = 닫음, non-nil = 표시 요청.
    var onShowClipDetailChange: (@MainActor (ClipDetailRequest?) -> Void)?
    /// TASK-030 — 클립 상세 sub-panel 표시 상태. `PopoverWindow` 가 `showClipDetailPanel` / `hideClipDetailPanel` 에서 갱신. `pinSidebarHoverExit` 안 가드에 사용 — 자식 sub-panel 떠 있는 동안 사이드바 자동 닫힘 차단.
    var isDetailPanelOpen: Bool = false
    /// 활성 행 frame (popover 좌표계, SwiftUI top-down). `HistoryPopover` / `PinSidebarView` 의 `GeometryReader` + `PreferenceKey` 가 게시.
    /// PopoverWindow 가 detail panel anchor + 꼭지 Y 계산에 사용.
    var activeRowFrameInPopover: CGRect = .zero {
        didSet {
            // frame 미세 변화는 무시 (`clipDetailFrameDeltaThreshold` 미만 변동은 Geometry update 폭주 차단).
            let threshold = DesignTokens.Spacing.clipDetailFrameDeltaThreshold
            if abs(oldValue.midY - activeRowFrameInPopover.midY) > threshold
                || abs(oldValue.minX - activeRowFrameInPopover.minX) > threshold {
                scheduleClipDetailUpdate()
            }
        }
    }
    private var clipDetailTask: Task<Void, Never>?
    /// 마지막 emit 한 clip.id 추적 (TASK-039 fix) — schedule 진입 시 clip 변경 검출 → 다른 clip 으로 변경되면 즉시 nil emit (panel hide). 같은 clip frame 변경 만 잔존 정책 적용.
    private var lastEmittedClipId: UUID?

    // MARK: - Dependencies
    private let repository: any ClipRepository
    private let pasteService: PasteService
    /// TASK-034 — 클립 삭제 시 디스크 카피본 cleanup. DB row 삭제 직후 호출 (delete / deleteAllExceptPinned).
    private let fileClipService: any FileClipService
    private weak var toastQueue: ToastQueue?
    /// TASK-043 — 클립보드 수집 토글 시 `setEnabled(_:)` 호출 대상. Composition Root 가 `setClipboardWatcher(_:)` 으로 주입. nil 인 단위 테스트 케이스 대비 옵셔널.
    private var clipboardWatcher: ClipboardWatcher?

    // MARK: - Capture toggle (TASK-043)

    /// 클립보드 수집 활성/비활성 상태. UserDefaults `Constants.clipboardCaptureEnabledKey` 진실 소스. init 시 UserDefaults 읽어 초기화. `toggleCapture()` 가 갱신.
    var captureEnabled: Bool

    init(
        repository: any ClipRepository,
        pasteService: PasteService,
        fileClipService: any FileClipService,
        toastQueue: ToastQueue? = nil
    ) {
        self.repository = repository
        self.pasteService = pasteService
        self.fileClipService = fileClipService
        self.toastQueue = toastQueue
        // TASK-043 — UserDefaults 미등록 시 true default (UserDefaults.bool 자연 fallback).
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Constants.clipboardCaptureEnabledKey) == nil {
            self.captureEnabled = true
        } else {
            self.captureEnabled = defaults.bool(forKey: Constants.clipboardCaptureEnabledKey)
        }
    }

    func setToastQueue(_ queue: ToastQueue) {
        self.toastQueue = queue
    }

    /// TASK-043 — Composition Root 가 ClipboardWatcher 인스턴스 주입. toggleCapture 호출 시 actor setEnabled 호출 대상.
    func setClipboardWatcher(_ watcher: ClipboardWatcher) {
        self.clipboardWatcher = watcher
    }

    /// TASK-043 — 클립보드 수집 토글 단일 진실 진입점. popover 상단 일시정지/재개 버튼이 호출.
    /// 흐름: (1) captureEnabled 상태 반전 (2) UserDefaults persist (3) NotificationCenter `captureEnabledDidChange` post (StatusItemController red dot 추종)
    ///       (4) ClipboardWatcher.setEnabled (actor 호출) (5) toastQueue success 발행.
    func toggleCapture() {
        let newValue = !captureEnabled
        captureEnabled = newValue
        UserDefaults.standard.set(newValue, forKey: Constants.clipboardCaptureEnabledKey)
        NotificationCenter.default.post(
            name: Constants.captureEnabledDidChangeNotification,
            object: nil,
            userInfo: ["enabled": newValue]
        )
        if let clipboardWatcher {
            Task { await clipboardWatcher.setEnabled(newValue) }
        }
        let messageKey: String.LocalizationValue = newValue ? "toast.capture.enabled" : "toast.capture.disabled"
        toastQueue?.enqueue(.success, String(localized: messageKey), ttl: DesignTokens.Animation.toastTTLCaptureToggle)
        Logger.ui.info("ClipsViewModel.toggleCapture: enabled=\(newValue, privacy: .public)")
    }

    /// TASK-024 — Composition Root 가 `PermissionService.statusPublisher` 구독 → 본 메서드로 권한 상태 갱신. 동적 토글 (사용자가 시스템 환경설정에서 권한 변경) 즉시 반영. SettingsViewModel.updateAccessibilityGranted 와 동일 패턴.
    func updateAccessibilityGranted(_ granted: Bool) {
        if accessibilityGranted != granted {
            accessibilityGranted = granted
            Logger.ui.info("ClipsViewModel.accessibilityGranted → \(granted, privacy: .public)")
        }
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
            // TASK-027 — same idx 자리 다른 clip 진입 케이스 (didSet 미발화). 명시 호출.
            scheduleClipDetailUpdate()
            // TASK-037 — visibleClips 변동 알림. autoFit ON 시 PopoverWindow 가 NSPanel frame 재계산.
            NotificationCenter.default.post(name: Self.displayLayoutDidChange, object: nil)
        } catch {
            Logger.ui.error("ClipsViewModel.reload error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func performSearch() async {
        do {
            let result = try await repository.search(query: searchQuery)
            clips = result
            selectedIdx = 0
            // TASK-027 — selectedIdx 가 이미 0 인 상태에서 = 0 박으면 didSet 미발화. 명시 호출.
            scheduleClipDetailUpdate()
            // TASK-037 — 검색 결과 변동도 visibleClips 변동. autoFit ON 시 컨테이너 자라남/줄어듦.
            NotificationCenter.default.post(name: Self.displayLayoutDidChange, object: nil)
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

    /// TASK-036 — ⌘+⇧+↑ 맨 위 (Home).
    func moveSelectionToFirst() {
        setSelection { _, _ in 0 }
    }

    /// TASK-036 — ⌘+⇧+↓ 맨 아래 (End).
    func moveSelectionToLast() {
        setSelection { _, count in count - 1 }
    }

    /// TASK-036 — ⌘+↑ 페이지 위 (토큰 추정 행 수만큼, 경계 clamp, wrap X).
    func pageUp() {
        let pageSize = effectivePageSize()
        setSelection { current, _ in max(0, current - pageSize) }
    }

    /// TASK-036 — ⌘+↓ 페이지 아래 (토큰 추정 행 수만큼, 경계 clamp, wrap X).
    func pageDown() {
        let pageSize = effectivePageSize()
        setSelection { current, count in min(count - 1, current + pageSize) }
    }

    /// TASK-036 — Edge / Page 점프 공통 처리. focusZone 분기 + 빈 리스트 가드 + idx 계산 + `pendingScrollToId` 세팅.
    /// `compute` 클로저 = `(currentIdx, count) -> newIdx`. moveSelectionUp/Down (TASK-021) 는 기존 코드 그대로 — 본 헬퍼 미사용.
    private func setSelection(compute: (_ currentIdx: Int, _ count: Int) -> Int) {
        if focusZone == .pin {
            let count = pinnedClips.count
            guard count > 0 else { return }
            pinSelectedIdx = compute(pinSelectedIdx, count)
            return
        }
        let list = visibleClips
        guard !list.isEmpty else { return }
        focusZone = .clip
        let newIdx = compute(selectedIdx, list.count)
        selectedIdx = newIdx
        pendingScrollToId = list[newIdx].id
    }

    /// TASK-036 — 페이지 점프 사이즈. TASK-037 으로 사용자 환경설정 N (UserDefaults `clipsPerPage`) 동적 조회.
    /// 매 호출 시점 최신값 조회 — 슬라이더 변경 즉시 다음 page jump 부터 반영.
    private func effectivePageSize() -> Int {
        let raw = UserDefaults.standard.integer(forKey: "clipsPerPage")
        return max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, raw))
    }

    /// TASK-037 — 디스플레이 환경설정 변경 시 NotificationCenter 채널. PopoverWindow 가 구독해서 NSPanel frame 동적 재계산.
    /// 트리거: (a) SettingsViewModel.setClipsPerPage/setAutoFitClipListHeight 호출 끝 / (b) reload() 끝 (visibleClips 변동 — autoFit ON 시 의미).
    static let displayLayoutDidChange = Notification.Name("stash.displayLayoutDidChange")

    /// TASK-037 — 클립 리스트 영역 동적 높이 계산 (순수 함수, 인자 명시).
    /// SwiftUI 가 `@AppStorage` 등으로 추적한 값을 호출처에서 전달해야 body 재계산이 트리거됨.
    /// 공식: autoFit ON → `rows = max(min(visibleCount, N), min(N, 3))` / OFF → `rows = N`.
    /// floor=3 룰: autoFit ON 시 컨테이너 최소 3행 보장. 단 N<3 시 N 우선.
    /// 화면 cap: popover 가 화면 visible 영역 초과 시 cap 적용 (popover top = visible.maxY 까지 박혀 menu bar 바로 아래에 붙음).
    static func effectiveClipListHeight(visibleCount: Int, clipsPerPage: Int, autoFit: Bool, hasPinned: Bool) -> CGFloat {
        let n = max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, clipsPerPage))
        let rowHeight = DesignTokens.Spacing.rowMinHeight
        let rowGap = DesignTokens.Spacing.rowGap
        let rows: Int
        if autoFit {
            // floor=3 룰: 최소 3행 보장 (단, N<3 인 경우 N 우선)
            rows = max(min(visibleCount, n), min(n, Constants.clipListAutoFitFloor))
        } else {
            rows = n
        }
        let raw = CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowGap
        // 화면 cap — clipList 외 SwiftUI body overhead (검색바 / 환설정행 / 힌트바 / popoverPadding × 2) 차감.
        // hasPinned 시 pinRow + margin 추가.
        let baseOverhead = DesignTokens.Spacing.clipListOverheadBase
        let pinRowOverhead: CGFloat = hasPinned ? (DesignTokens.Spacing.pinRowHeight + DesignTokens.Spacing.pinRowMarginVert * 2) : 0
        let totalOverhead = baseOverhead + pinRowOverhead
        let screenAvailable = (NSScreen.main?.visibleFrame.height ?? 800) - totalOverhead
        let cap = max(rowHeight, screenAvailable)  // 최소 1행 보장
        return min(raw, cap)
    }

    /// TASK-037 — UserDefaults 직접 조회 wrapper. SwiftUI 외부 호출용.
    static func effectiveClipListHeightFromUserDefaults(visibleCount: Int, hasPinned: Bool) -> CGFloat {
        let n = UserDefaults.standard.integer(forKey: "clipsPerPage")
        let autoFit = UserDefaults.standard.bool(forKey: "autoFitClipListHeight")
        return effectiveClipListHeight(visibleCount: visibleCount, clipsPerPage: n, autoFit: autoFit, hasPinned: hasPinned)
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

    /// hover 시 focusZone 자동 변경 (popover.jsx L329 / L470 정합).
    /// TASK-025 — `.search` case 폐기. 검색바 hover 는 focusZone 변경 X (always-active). 행 (`.clip` / `.pin` / `.settings`) hover 만 갱신.
    /// popover 열림 직후 200ms는 hover 무시 — 마우스가 행 위에 미리 있어도 비활성 상태 유지.
    func setFocusZone(_ zone: FocusZone) {
        if isHoverIgnored { return }
        if focusZone != zone {
            focusZone = zone
        }
    }

    /// popover 열림 시 호출 — 초기 상태 reset (focusZone=.clip + selectedIdx=0 + searchQuery 비움).
    /// 사용자가 popover 열 때마다 가장 최신 클립이 선택 커서로 활성된 상태. 검색바는 always-active 정책으로 별도 active state 없음 (TASK-025).
    /// 마우스가 행 위에 이미 있어도 200ms 동안 hover 무시 — 자동 활성 차단.
    func resetForOpen() {
        focusZone = .clip
        selectedIdx = 0
        searchQuery = ""
        pinSidebarOpen = false
        pinHoverActive = false
        pendingScrollToId = nil
        ignoreHoverUntil = Date().addingTimeInterval(DesignTokens.Animation.popoverOpenHoverIgnoreDelay)
        // TASK-027 — popover 새 호출 시 detail panel 강제 닫음. frame .zero 초기화도 함께.
        activeRowFrameInPopover = .zero
        scheduleClipDetailUpdate()
    }

    // MARK: - Actions

    /// TASK-028 — paste / copy 의 zone 분기 + idx 경계 가드 + clip 선택을 단일 helper 로 분리.
    /// `zone == .pin` → `pinnedClips[idx]`, 그 외 → `visibleClips[idx]`. 가드 미통과 시 nil + debug 로그.
    private func clipForZone(at idx: Int, zone: FocusZone) -> Clip? {
        if zone == .pin {
            guard idx >= 0 && idx < pinnedClips.count else {
                Logger.ui.debug("Clip lookup skip — zone=.pin idx=\(idx, privacy: .public) pinnedClips.count=\(self.pinnedClips.count, privacy: .public)")
                return nil
            }
            return pinnedClips[idx]
        }
        let list = visibleClips
        guard idx >= 0 && idx < list.count else {
            Logger.ui.debug("Clip lookup skip — zone=.clip idx=\(idx, privacy: .public) visibleClips.count=\(list.count, privacy: .public)")
            return nil
        }
        return list[idx]
    }

    /// TASK-019 fix 2차 — zone == .pin 일 때 *pinnedClips 안 항목* paste. 본체 visibleClips 는 zone == .clip 일 때만.
    /// TASK-024 — 권한 X 시 effective mode 를 `.copyBack` 강제. 마우스 클릭 진입점 대비 안전망 (⌘V 단축키는 `PopoverPanel.dispatch` 단계에서 차단되어 본 메서드 호출 X).
    /// TASK-028 — `zone` 명시 파라미터화. 호출 시점 zone snapshot 으로 결정하므로 `hide()` → `collapsePinSidebar()` → `focusZone = .clip` 후속 흐름이 paste 대상에 영향 X. zone 분기 + 가드는 `clipForZone(at:zone:)` 로 분리.
    func paste(at idx: Int, zone: FocusZone) async {
        guard let clip = clipForZone(at: idx, zone: zone) else { return }
        Logger.ui.info("Paste invoked — zone=\(zone.rawValue, privacy: .public) idx=\(idx, privacy: .public) clipId=\(clip.id.uuidString, privacy: .public)")
        // TASK-033 — autoPasteEnabled (UserDefaults 단일 진실 소스) × accessibilityGranted 매트릭스. 둘 다 true 시에만 auto-paste, 외는 copy back fallback. UserDefaults default true 는 Composition Root 가 register defaults 로 박음.
        let autoPasteEnabled = UserDefaults.standard.bool(forKey: "autoPasteEnabled")
        let effectiveMode: PasteMode = (accessibilityGranted && autoPasteEnabled) ? .autoPaste : .copyBack
        do {
            try await pasteService.paste(clip: clip, mode: effectiveMode)
            triggerPasteFlash(for: clip.id)
            publishPasteToast(for: clip, mode: effectiveMode)
        } catch {
            Logger.ui.error("ClipsViewModel.paste error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishPasteToast(for clip: Clip, mode: PasteMode) {
        guard let toastQueue else { return }
        let snippet = String((clip.body ?? "").prefix(20))
        if mode == .autoPaste {
            toastQueue.enqueue(.success, String(localized: "toast.paste.done") + ": \(snippet)", ttl: DesignTokens.Animation.toastTTLShort)
        } else {
            // TASK-033 — *바로 붙여넣기* OFF 또는 권한 X 상태 popover 클립 선택 시 단축키 안내 없는 단순 토스트 (UX-UI §6-1 *⌘+C 복사 확정 / 자동 paste OFF popover 선택* 통합 행 정합).
            toastQueue.enqueue(.success, String(localized: "toast.copy.done"), ttl: DesignTokens.Animation.toastTTLShort)
        }
    }

    /// TASK-024 — ⌘+C 복사 단축키 액션. Settings `pasteMode` 라디오 무관 *항상* `.copyBack` 모드 호출 — 클립보드 갱신만, ⌘V 합성 X. Accessibility 권한 무관 항상 활성. zone == .pin / .clip 분기는 paste(at:zone:) 와 동일.
    /// TASK-028 — `zone` 명시 파라미터화. paste(at:zone:) 와 동일 사유. zone 분기 + 가드는 `clipForZone(at:zone:)` 로 분리.
    func copy(at idx: Int, zone: FocusZone) async {
        guard let clip = clipForZone(at: idx, zone: zone) else { return }
        Logger.ui.info("Copy invoked — zone=\(zone.rawValue, privacy: .public) idx=\(idx, privacy: .public) clipId=\(clip.id.uuidString, privacy: .public) type=\(clip.type.rawValue, privacy: .public)")
        do {
            try await pasteService.paste(clip: clip, mode: .copyBack)
            triggerPasteFlash(for: clip.id)
            publishCopyToast()
        } catch {
            Logger.ui.error("ClipsViewModel.copy error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishCopyToast() {
        guard let toastQueue else { return }
        toastQueue.enqueue(.success, String(localized: "toast.copy.done"), ttl: DesignTokens.Animation.toastTTLShort)
    }

    // TASK-020 — pop(at:) 함수 제거 (⌘⇧V 단축키·기능 일괄 폐기로 호출처 0건).

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
    /// TASK-034 — DB row 삭제 후 디스크 카피본 cleanup. 텍스트 클립은 `DirectFileClipService.delete` 내부 guard (`filePath == nil`) 로 no-op.
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
        try? await fileClipService.delete(clip)
        await reload()
        clampSelection()
    }

    /// TASK-034 — DB 삭제 + entry 별 디스크 cleanup + 핀 참조 외 clips/ 폴더 sweep (누적 고아 + 디스크 삭제 실패 fallback 회수).
    func deleteAllExceptPinned() async {
        let deleted = (try? await repository.deleteAllExceptPinned()) ?? []
        for clip in deleted {
            try? await fileClipService.delete(clip)
        }
        let pinnedPaths = collectReferencedPaths(from: pinnedClips)
        await fileClipService.sweepOrphans(referencedPaths: pinnedPaths)
        await reload()
        selectedIdx = 0
        toastQueue?.enqueue(.info, String(localized: "toast.deleteAll.done"), ttl: DesignTokens.Animation.toastTTLLong)
    }

    /// TASK-034 — 클립 배열 → clips/ 폴더 안 참조 절대경로 set. `isFileExternal=false` 만 (외부 원본은 stash 카피본 X — sweep 대상 X).
    /// 단일 파일 (`filePath`) + 다중 파일 묶음 (`fileEntries[].filePath`) 모두 수집.
    private func collectReferencedPaths(from clips: [Clip]) -> Set<String> {
        var paths: Set<String> = []
        for clip in clips {
            if clip.isMultiFile, let entries = clip.fileEntries {
                for entry in entries where !entry.isFileExternal {
                    paths.insert(entry.filePath)
                }
            } else if !clip.isFileExternal, let path = clip.filePath {
                paths.insert(path)
            }
        }
        return paths
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
        // TASK-030 — 클립 상세 sub-panel 떠 있는 동안 사이드바 닫힘 차단. 사용자가 사이드바 → 상세 sub-panel 마우스 이동 시 사이드바가 자동 닫히는 버그 회피.
        if isDetailPanelOpen { return }
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

    // MARK: - Clip Detail sub-window (TASK-027)

    /// 4축 (focusZone / selectedIdx / pinSelectedIdx / activeRowFrameInPopover) 중 어느 하나 변경 시 호출.
    /// 즉시 현재 detail 닫고 (콜백 nil) 활성 행이 다중파일이면 200ms 후 detail 재오픈 (콜백 ClipDetailRequest).
    /// `reload` / `performSearch` 후 *같은 idx 자리 다른 clip* 진입 케이스도 명시 호출로 잡음 (didSet 미발화 케이스 대비).
    func scheduleClipDetailUpdate() {
        clipDetailTask?.cancel()
        clipDetailTask = nil

        // TASK-039 — emit 정책:
        // - 매칭 X (활성 없음 / Provider nil / frame 미게시) → 즉시 nil emit (panel hide).
        // - 매칭 O + clip 변경 (lastEmittedClipId != active.clip.id) → 즉시 nil emit (hover 이동 시 즉각 사라짐).
        // - 매칭 O + 같은 clip → 기존 panel 잔존 + 200ms 후 갱신 (깜빡임 차단).
        let active = activeClipForDetail()
        let provider = active.map { ClipDetailRegistry.provider(for: $0.clip) } ?? nil

        guard let active,
              provider != nil,
              activeRowFrameInPopover != .zero else {
            onShowClipDetailChange?(nil)
            lastEmittedClipId = nil
            return
        }

        if let lastId = lastEmittedClipId, lastId != active.clip.id {
            onShowClipDetailChange?(nil)
            lastEmittedClipId = nil
        }

        let snapshotClipId = active.clip.id
        let snapshotZone = active.zone
        clipDetailTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.Animation.clipDetailDebounceDelay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            // 200ms 사이 활성 변경 가능 — 재검증.
            guard let current = self.activeClipForDetail(),
                  current.clip.id == snapshotClipId,
                  current.zone == snapshotZone else { return }
            guard self.activeRowFrameInPopover != .zero else { return }

            let req = ClipDetailRequest(
                clip: current.clip,
                zone: current.zone,
                rowFrameInPopover: self.activeRowFrameInPopover
            )
            Logger.ui.debug("ClipDetail: emit request — clipId=\(snapshotClipId.uuidString, privacy: .public) zone=\(String(describing: snapshotZone), privacy: .public)")
            self.lastEmittedClipId = current.clip.id
            self.onShowClipDetailChange?(req)
        }
    }

    /// 현재 활성 클립 (focusZone 분기). 경계 검사 — 잘못된 idx 또는 빈 리스트 시 nil.
    /// `.clip` / `.pin` 외 zone (`.settings` 등) 은 nil 반환 — detail panel 잔존 차단 (TASK-039 fix).
    private func activeClipForDetail() -> (clip: Clip, zone: FocusZone)? {
        switch focusZone {
        case .clip:
            let list = visibleClips
            guard selectedIdx >= 0, selectedIdx < list.count else { return nil }
            return (list[selectedIdx], .clip)
        case .pin:
            let pins = pinnedClips
            guard pinSelectedIdx >= 0, pinSelectedIdx < pins.count else { return nil }
            return (pins[pinSelectedIdx], .pin)
        default:
            // `.settings` 등 — detail panel 미진입 (TASK-039 fix). focusZone 변경 시 즉시 nil emit → detail 닫음.
            return nil
        }
    }
}
