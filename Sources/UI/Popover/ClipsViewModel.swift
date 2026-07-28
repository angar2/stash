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
            // activeRowFrameInPopover reset (.zero) → 새 zone 행 frame 게시 시 정확 좌표 emit (트리거 발화 후).
            activeRowFrameInPopover = .zero
            // TASK-055 — zone 변경 = 클립 커서 이동의 일종 → 즉시 close (단일 룰).
            dismissClipDetail()
        }
    }
    var selectedIdx: Int = 0 {
        didSet {
            // TASK-055 — 행 변경 = 즉시 close (단일 룰). 새 행에서 sub-window 보려면 재트리거 필요.
            if oldValue != selectedIdx { dismissClipDetail() }
        }
    }
    // TASK-025 — `searchInputActive` 폐기. 검색바 always-active 정책으로 활성 단계 개념 제거.
    /// TASK-024 — Accessibility 권한 게이트 state. `PermissionService.statusPublisher` 구독으로 Composition Root 가 갱신. 권한 X 시 ⌘V 비활성 (PopoverPanel.dispatch 게이트) + 힌트바 회색조 (KeyboardHintsView 분기).
    var accessibilityGranted: Bool = false
    var pinSidebarOpen: Bool = false {    // Pin 사이드 펼침 여부
        didSet {
            // TASK-019 — `PopoverWindow`가 별도 NSPanel 호스팅 토글. @Observable stored property 의 didSet 정상 동작.
            if oldValue != pinSidebarOpen {
                onPinSidebarOpenChange?(pinSidebarOpen)
                // TASK-055 — 사이드바 상태 변경 = 클립 커서 컨텍스트 변경 → close 단일 룰.
                dismissClipDetail()
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
            // TASK-055 — Pin 사이드바 안 행 변경 = 즉시 close (단일 룰).
            if oldValue != pinSelectedIdx { dismissClipDetail() }
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
    /// TASK-062 — `pinSidebarHoverExit()` 가드 closure. `PopoverWindow` 가 등록 — NSEvent.mouseLocation + 핀 사이드바 frame + 상세 sub-panel frame 합집합 검사 후 bool 반환. true = close 차단 (합집합 안), false = close 진행 (합집합 밖). 기존 TASK-030 의 `isDetailPanelOpen` boolean 가드 대체 — boolean 만 검사 + 위치 영역 검사 X 결함 정합.
    var shouldRetainPinSidebarOnHoverExit: (@MainActor () -> Bool)?
    /// 활성 행 frame (popover 좌표계, SwiftUI top-down). `HistoryPopover` / `PinSidebarView` 의 `GeometryReader` + `PreferenceKey` 가 게시.
    /// PopoverWindow 가 detail panel anchor + 꼭지 Y 계산에 사용.
    var activeRowFrameInPopover: CGRect = .zero {
        didSet {
            // frame 미세 변화는 무시 (`clipDetailFrameDeltaThreshold` 미만 변동은 Geometry update 폭주 차단).
            let threshold = DesignTokens.Spacing.clipDetailFrameDeltaThreshold
            guard abs(oldValue.midY - activeRowFrameInPopover.midY) > threshold
                || abs(oldValue.minX - activeRowFrameInPopover.minX) > threshold else { return }
            // TASK-055 — 같은 행 frame 미세 변경 (popover 드래그 / resize / 검색 결과 재배치 등) → 표시 중일 때만 anchor 재계산 (panel 위치 따라감). 미표시 시 no-op.
            guard clipDetailVisible else { return }
            emitClipDetailRequestIfMatching()
        }
    }
    /// TASK-055 — 클립 상세 sub-window 표시 상태. toggle close 분기 + close 단일 룰 진입 가드.
    private(set) var clipDetailVisible: Bool = false
    /// TASK-055 — hover 임계 timer + 현재 추적 row.id. `hoverEnterRow(id:)` 가 같은 row.id 진입 시 task 보존 (미세 움직임 누적). 다른 row.id 시 cancel + 재시작.
    private var hoverDetailTask: Task<Void, Never>?
    private var hoverDetailTaskRowId: UUID?
    /// 마지막 emit 한 clip.id 추적 (TASK-039 fix) — schedule 진입 시 clip 변경 검출 → 다른 clip 으로 변경되면 즉시 nil emit (panel hide). 같은 clip frame 변경 만 잔존 정책 적용.
    private var lastEmittedClipId: UUID?

    /// TASK-061 — 검색 디바운스 in-flight Task. `scheduleSearch()` 가 매 호출 시 이전 task cancel 후 새 task 박음. plan F-009 `Constants.searchDebounce` 정합.
    /// 사유: 키 입력마다 `performSearch` 즉시 호출 시 (a) 여러 in-flight Task race + (b) 매 호출 끝 `displayLayoutDidChange` notification → `PopoverWindow.refreshFrame` → setFrame 다중 발화 → height oscillation.
    private var pendingSearchTask: Task<Void, Never>?

    /// TASK-061 — max wait 패턴. 첫 `scheduleSearch()` 호출 시점에 `Constants.searchMaxWait` 더한 deadline 박음. 후속 호출 시 deadline 유지 → 디바운스 vs maxWait 중 *먼저 도달* 시 fire. fire 후 nil reset (다음 사이클 새 deadline).
    /// 효과: 사용자 200ms 미만 간격 연속 타이핑 (예: ㅂ→보→복→...) 시도 500ms 마다 강제 fire → *완전히 다 작성할 때까지 결과 안 박힘* 차단.
    private var searchMaxWaitDeadline: ContinuousClock.Instant?

    // MARK: - Dependencies
    private let repository: any ClipRepository
    private let pasteService: PasteService
    /// TASK-034 — 클립 삭제 시 디스크 카피본 cleanup. DB row 삭제 직후 호출 (delete / deleteAllExceptPinned).
    private let fileClipService: any FileClipService
    private weak var toastQueue: ToastQueue?
    /// TASK-043 — 클립보드 수집 토글 시 `setEnabled(_:)` 호출 대상. Composition Root 가 `setClipboardWatcher(_:)` 으로 주입. nil 인 단위 테스트 케이스 대비 옵셔널.
    private var clipboardWatcher: ClipboardWatcher?

    // MARK: - Capture toggle (TASK-043)

    /// 클립보드 수집 활성/비활성 상태. UserDefaults `Constants.UserDefaultsKeys.clipboardCaptureEnabled` 진실 소스. init 시 UserDefaults 읽어 초기화. `toggleCapture()` 가 갱신.
    var captureEnabled: Bool

    // MARK: - Keep open toggle (TASK-058)

    /// TASK-058 — popover 유지 모드 토글 상태. ON 시 paste/copy 후 popover `hide()` 호출 skip → 연속 paste/copy 가능. *세션 한정 영속성* — UserDefaults 미저장. popover 명시적 dismiss (`PopoverWindow.hide()`) 시점에 false 리셋.
    var keepOpenAfterAction: Bool = false

    /// TASK-058 fix-1 — `clipboardDidInsertClip` 알림 옵저버. ClipsViewModel lifetime 동안 유지 (Singleton 패턴 — 앱 quit 까지). deinit 정리는 @MainActor isolation 한계로 생략 (앱 quit 시 자연 회수).
    private var clipboardInsertObserver: NSObjectProtocol?

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
        if defaults.object(forKey: Constants.UserDefaultsKeys.clipboardCaptureEnabled) == nil {
            self.captureEnabled = true
        } else {
            self.captureEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.clipboardCaptureEnabled)
        }
        // TASK-058 fix-1 — ClipboardWatcher insert 알림 구독. popover 떠있는 상태 (특히 유지 모드 ON) 에서 즉시 reload — 사용자가 popover 열어둔 채 다른 앱에서 클립 복사 시 popover 안 즉시 새 클립 반영.
        self.clipboardInsertObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.clipboardDidInsertClip,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reload()
            }
        }
    }

    func setToastQueue(_ queue: ToastQueue) {
        self.toastQueue = queue
    }

    /// TASK-043 — Composition Root 가 ClipboardWatcher 인스턴스 주입. toggleCapture 호출 시 actor setEnabled 호출 대상.
    func setClipboardWatcher(_ watcher: ClipboardWatcher) {
        self.clipboardWatcher = watcher
    }

    /// TASK-058 — popover 유지 모드 토글 단일 진실 진입점. popover 상단 자물쇠 아이콘 버튼이 호출.
    /// 흐름: `keepOpenAfterAction` 상태 반전 단일 라인. UserDefaults persist X (세션 한정), 토스트 X (아이콘 fill 변화 자체 피드백 — FEATURES F-011 정합).
    func toggleKeepOpenAfterAction() {
        keepOpenAfterAction.toggle()
        Logger.ui.info("ClipsViewModel.toggleKeepOpenAfterAction: enabled=\(self.keepOpenAfterAction, privacy: .public)")
    }

    /// TASK-043 — 클립보드 수집 토글 단일 진실 진입점. popover 상단 일시정지/재개 버튼이 호출.
    /// 흐름: (1) captureEnabled 상태 반전 (2) UserDefaults persist (3) NotificationCenter `captureEnabledDidChange` post (StatusItemController red dot 추종)
    ///       (4) ClipboardWatcher.setEnabled (actor 호출) (5) toastQueue success 발행.
    func toggleCapture() {
        let newValue = !captureEnabled
        captureEnabled = newValue
        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKeys.clipboardCaptureEnabled)
        NotificationCenter.default.post(
            name: Constants.Notifications.captureEnabledDidChange,
            object: nil,
            userInfo: ["enabled": newValue]
        )
        if let clipboardWatcher {
            Task { await clipboardWatcher.setEnabled(newValue) }
        }
        let messageKey = newValue ? "toast.capture.enabled" : "toast.capture.disabled"
        toastQueue?.enqueue(.success, L10n(messageKey))
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
    // TASK-061 — `clips.filter(searchQuery contains)` 클라이언트 필터 제거. searchQuery 의존 → SwiftUI body 가 매 키 입력마다 즉시 재계산 → visibleClips 변동 시각 (디바운스 무용지물).
    // 검색은 디바운스 후 `performSearch` 가 DB 검색 결과로 `clips` 박음 → 그때만 SwiftUI body 재계산 → 사용자 키 입력 ~ 디바운스 임계 사이 *완전 무변동* 보장.
    // DB 검색 (`repository.search`) 결과 = `body contains query` 동일 의미 → 클라이언트 필터 제거 후에도 결과 일치.
    var filteredClips: [Clip] {
        clips
    }

    /// popover 본문 — 일반 히스토리에 *Pin 항목도 시간순 자연 노출* (FEATURES §3-4 / F-004 정합, TASK-019 fix).
    /// 이전 코드: `filteredClips.filter { !$0.isPinned }` — plan과 어긋난 버그. 핀 토글 시 일반 목록에서 사라짐 문제 발생.
    /// 현재: 모든 클립 노출. 핀 시각 구분은 `ClipRowView`가 `clip.isPinned` 분기로 자동 (행 우측 파란 압정 아이콘).
    var visibleClips: [Clip] {
        filteredClips
    }

    /// Pin 사이드바 — 핀 항목 별도 보장 노출 채널 (일반 히스토리 외 추가 채널).
    /// 정렬 = **자리 번호(`pin_slot`) 오름차순** (TASK-098 검수 정정).
    ///
    /// 정책이 두 번 바뀐 자리라 근거를 남긴다. TASK-019 는 `pinned_at DESC`(최근 핀이 상단)였고, TASK-098 이 이를 뒤집었다 —
    /// Pin 직접 paste 단축키가 *순번* 을 대상 지정 수단으로 쓰는데 최근 핀 상단 정렬에서는 새 핀마다 전체 번호가 밀려
    /// `⌥⌘1` 이 가리키는 대상이 수시로 바뀌기 때문이다. 그러나 시각 순서만으로는 *핀 해제* 시 뒤 항목이 당겨지는 것을
    /// 막지 못해(검수 지적) 자리를 데이터로 갖게 했다. 이제 해제해도 그 자리만 비므로 **중간이 비는 것이 정상 상태**다(1·3·4).
    /// 사이드바는 빈 자리를 건너뛰어 나열하되 각 행은 자기 번호를 표시한다.
    ///
    /// 자리가 없는 행(V7 이전 데이터 안전망)은 옛 기준(`pinned_at`, NULL 은 `created_at`) 오름차순으로 자리 있는 행 뒤에 둔다.
    var pinnedClips: [Clip] {
        clips.filter { $0.isPinned }.sorted { lhs, rhs in
            switch (lhs.pinSlot, rhs.pinSlot) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return (lhs.pinnedAt ?? lhs.createdAt) < (rhs.pinnedAt ?? rhs.createdAt)
            }
        }
    }

    /// TASK-098 검수 정정 — *자리 번호* 로 핀을 찾는다. 단축키 순번 · 설정 행 번호가 모두 이 경로를 쓴다.
    /// 배열 위치(`pinnedClips[n-1]`)로 찾으면 앞자리가 빈 순간 다른 클립을 가리킨다.
    func pinnedClip(atSlot slot: Int) -> Clip? {
        pinnedClips.first { $0.pinSlot == slot }
    }

    /// `focusZone` 기반 현재 활성 idx — `.pin` 이면 `pinSelectedIdx`, 그 외는 `selectedIdx`.
    /// dispatch site 의 반복 패턴 (`focusZone == .pin ? pinSelectedIdx : selectedIdx`) 정리 (TASK-019 리팩토링).
    var activeIdx: Int {
        focusZone == .pin ? pinSelectedIdx : selectedIdx
    }

    // MARK: - 다중 선택 (TASK-099)

    /// 선택한 클립 id — **선택한 순서 그대로**. 이 배열이 기능 전체의 단일 진실이다
    /// (순서 칩 · 프리뷰 · 묶음 실행 · `⌘C`/`⌘V` 분기가 모두 여기를 본다).
    /// 비어 있으면 *기존 단일 동작* 경로가 그대로 돈다 — 회귀 위험이 조건 하나로 좁혀지는 자리라 의미가 크다.
    private(set) var multiSelection: [UUID] = []

    /// 선택 시점의 클립 사본. **검색 때문에 필요하다** — 검색은 `clips` 를 결과로 통째 갈아끼우므로
    /// 선택한 클립이 필터에서 빠지면 `clips` 조회만으로는 프리뷰가 사라진다(요구: 검색 중에도 선택·프리뷰 유지).
    /// 조회는 언제나 `clips` 를 먼저 보고 없을 때만 이 사본으로 떨어진다 — 본문이 수정돼도 최신값을 쓰기 위해서다.
    private var multiSelectionSnapshots: [UUID: Clip] = [:]

    /// 선택한 클립들 — 선택 순서 그대로.
    var multiSelectedClips: [Clip] {
        multiSelection.compactMap { id in
            clips.first { $0.id == id } ?? multiSelectionSnapshots[id]
        }
    }

    /// 행에 겹쳐 그릴 선택 순서(1-based). 선택 안 된 클립은 nil.
    func multiSelectOrdinal(for id: UUID) -> Int? {
        multiSelection.firstIndex(of: id).map { $0 + 1 }
    }

    /// 선택 토글 — 이미 선택된 클립이면 해제한다. 해제하면 뒤 순번이 자연히 앞으로 당겨진다(배열 제거).
    /// 대상은 히스토리 목록과 Pin 사이드바 **양쪽**이다 (fix-4). 판정 기준이 `clips` 하나라
    /// 핀 여부는 애초에 구분되지 않는다 — 어느 목록에서 집었든 같은 클립이면 선택은 한 건이고 순번도 하나다.
    /// `clips` 에 없는 id 는 무시한다 (이미 사라진 클립을 가리키는 stale 콜백 방어).
    func toggleMultiSelect(id: UUID) {
        if let idx = multiSelection.firstIndex(of: id) {
            multiSelection.remove(at: idx)
            multiSelectionSnapshots[id] = nil
            Logger.ui.info("MultiSelect 해제 — clipId=\(id.uuidString, privacy: .public) 남은 선택=\(self.multiSelection.count, privacy: .public)")
        } else {
            guard let clip = clips.first(where: { $0.id == id }) else {
                Logger.ui.debug("MultiSelect skip — 목록에 없는 clipId=\(id.uuidString, privacy: .public)")
                return
            }
            multiSelection.append(id)
            multiSelectionSnapshots[id] = clip
            Logger.ui.info("MultiSelect 선택 — clipId=\(id.uuidString, privacy: .public) 순번=\(self.multiSelection.count, privacy: .public)")
        }
        // 프리뷰 바가 나타나거나 사라지면 popover 높이가 그만큼 달라진다.
        NotificationCenter.default.post(name: Self.displayLayoutDidChange, object: nil)
    }

    /// 선택 단축키(`⌥C`)가 가리키는 **현재 커서 행**을 토글한다. 대상은 `focusZone` 이 정한다 —
    /// `.clip` 이면 히스토리 커서, `.pin` 이면 Pin 사이드바 커서.
    ///
    /// 판정을 dispatch 가 아니라 여기 두는 이유는 **검증 가능성**이다. fix-1 에서 실행 흐름이
    /// dispatch 안에만 있어 단위 테스트가 통째로 비껴간 전례가 있다.
    ///
    /// - Returns: 실제로 토글했으면 true. 대상 행이 없거나(빈 목록·커서 범위 밖) 선택 대상이 아닌
    ///   zone 이면 false — **호출처는 이 값과 무관하게 키 이벤트를 소비해야 한다**
    ///   (forward 하면 검색란에 `ç` 가 입력된다).
    @discardableResult
    func toggleMultiSelectAtActiveRow() -> Bool {
        let target: Clip?
        switch focusZone {
        case .clip:
            let list = visibleClips
            target = list.indices.contains(selectedIdx) ? list[selectedIdx] : nil
        case .pin:
            // fix-4 — Pin 사이드바도 선택 대상. 커서는 히스토리와 별도(`pinSelectedIdx`)다.
            let list = pinnedClips
            target = list.indices.contains(pinSelectedIdx) ? list[pinSelectedIdx] : nil
        case .settings:
            target = nil
        }
        guard let clip = target else {
            Logger.ui.debug("MultiSelect skip — 대상 행 없음 zone=\(self.focusZone.rawValue, privacy: .public)")
            return false
        }
        toggleMultiSelect(id: clip.id)
        return true
    }

    /// 전체 해제. 호출 site = `ESC`(선택 있을 때) / 묶음 실행 직후 / popover 열림·닫힘.
    func clearMultiSelection() {
        guard !multiSelection.isEmpty else { return }
        Logger.ui.info("MultiSelect 전체 해제 — 해제 개수=\(self.multiSelection.count, privacy: .public)")
        multiSelection.removeAll()
        multiSelectionSnapshots.removeAll()
        NotificationCenter.default.post(name: Self.displayLayoutDidChange, object: nil)
    }

    /// 선택 목록에서 특정 클립을 걷어낸다 — **삭제 경로 전용**.
    /// 검색 필터로 안 보이는 것과 실제로 사라진 것을 구분해야 하므로, 목록 조회 결과가 아니라
    /// *삭제한 id* 로만 걷어낸다 (조회 기준으로 prune 하면 검색 중에 선택이 통째로 날아간다).
    func pruneMultiSelection(deletedIds: [UUID]) {
        guard !multiSelection.isEmpty, !deletedIds.isEmpty else { return }
        let removing = Set(deletedIds)
        let before = multiSelection.count
        multiSelection.removeAll { removing.contains($0) }
        for id in removing { multiSelectionSnapshots[id] = nil }
        guard before != multiSelection.count else { return }
        Logger.ui.info("MultiSelect prune — 삭제로 제외=\(before - self.multiSelection.count, privacy: .public) 남은 선택=\(self.multiSelection.count, privacy: .public)")
        NotificationCenter.default.post(name: Self.displayLayoutDidChange, object: nil)
    }

    /// 설정에 저장된 연결자 **원문**. 미설정이면 기본값(줄바꿈 표기).
    /// 빈 문자열은 *구분 없이 연결* 이라는 유효한 값이라 `?? 기본값` 이 아니라 키 부재로만 fallback 한다.
    static var multiPasteSeparatorRaw: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
            ?? Constants.multiPasteSeparatorDefault
    }

    /// 프리뷰 바 내용. 선택이 없으면 nil (= 바 미표시).
    /// 화면은 `@AppStorage` 로 연결자를 추적해 직접 `MultiPasteComposer.preview` 를 부른다(즉시 반영 필요).
    /// 이 프로퍼티는 화면 밖 호출처(로그·테스트)용 동일 결과다.
    var multiPastePreview: MultiPastePreview? {
        MultiPasteComposer.preview(clips: multiSelectedClips, separatorRaw: Self.multiPasteSeparatorRaw)
    }

    // MARK: - 묶음 실행 (TASK-099)

    /// 묶음 실행을 부른 단축키. `⌘C` 는 클립보드 갱신만, `⌘V` 는 붙여넣기까지.
    enum MultiPasteAction: Sendable {
        case copy
        case paste
    }

    /// 실행할 수 없는 이유. 있으면 **popover 를 닫지 않고** 안내만 하고 선택도 유지한다
    /// (닫아버리면 사용자가 무엇이 막혔는지 확인할 화면이 사라진다).
    enum MultiPasteBlockReason: Sendable {
        /// 혼합 선택의 복사 — 연속 합성은 붙여넣기 전제라 복사로 표현할 단일 산출물이 없다.
        case mixedCopyUnsupported
        /// 혼합 선택의 붙여넣기 — 자동 붙여넣기 + 시스템 접근 권한이 있어야 순서가 성립한다.
        case mixedNeedsAutoPaste
    }

    /// 묶음 실행이 막히는 경우를 *실행 전에* 판정한다. nil = 실행 가능.
    /// - Parameter clips: 판정 대상을 명시할 때 사용 (nil 이면 현재 선택). 실행 대상과 판정 대상이
    ///   어긋나면 막아야 할 조합이 그대로 실행되므로, 스냅샷을 쓰는 흐름은 같은 배열을 넘긴다.
    func multiPasteBlockReason(for action: MultiPasteAction, clips: [Clip]? = nil) -> MultiPasteBlockReason? {
        guard MultiPasteComposer.category(of: clips ?? multiSelectedClips) == .mixed else { return nil }
        if action == .copy { return .mixedCopyUnsupported }
        return effectivePasteMode == .autoPaste ? nil : .mixedNeedsAutoPaste
    }

    /// 안내 토스트만 발행 (실행 없음 · 선택 유지).
    func publishMultiPasteBlockedToast(_ reason: MultiPasteBlockReason) {
        let key: String
        switch reason {
        case .mixedCopyUnsupported: key = "toast.multiPaste.mixed.copyUnsupported"
        case .mixedNeedsAutoPaste:  key = "toast.multiPaste.mixed.needsAutoPaste"
        }
        Logger.ui.info("MultiPaste 차단 — 사유=\(String(describing: reason), privacy: .public)")
        toastQueue?.enqueue(.warn, L10n(key))
    }

    /// *바로 붙여넣기* 설정 조회. 기본은 UserDefaults 이며, 단위 테스트가 **전역 상태에 흔들리지 않도록** 주입 가능하게 둔다
    /// (여러 스위트가 같은 키를 지우고 쓰는데 스위트는 병렬로 돌아, 조회 시점 값이 남의 것일 수 있다).
    var autoPasteEnabledProvider: () -> Bool = {
        UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
    }

    /// 붙여넣기 모드 판정의 **단일 소스** — 자동 붙여넣기 설정 × 시스템 접근 권한 (TASK-033 매트릭스).
    /// 둘 다 참일 때만 자동 붙여넣기, 아니면 복사 폴백. 단일 클립(`paste(at:zone:)`)과 묶음 실행이 같이 쓴다.
    private var effectivePasteMode: PasteMode {
        (accessibilityGranted && autoPasteEnabledProvider()) ? .autoPaste : .copyBack
    }

    /// 묶음 실행 진입점. 계열에 따라 [텍스트 연결 / 파일 배열 / 혼합 연속] 세 갈래로 갈린다.
    /// 실행에 성공하면 결과를 새 클립으로 등록하고(혼합 제외) 선택을 비운다.
    /// - Parameter clips: 실행 대상을 **호출자가 미리 확정해 넘길 때** 사용한다.
    ///   popover 를 내리고 붙이는 흐름에서는 `hide()` 가 닫힘과 함께 선택을 비우므로,
    ///   여기서 상태를 다시 읽으면 빈 선택을 보고 아무것도 하지 않는다. nil 이면 현재 선택을 쓴다.
    func runMultiPaste(_ action: MultiPasteAction, clips: [Clip]? = nil) async {
        let selected = clips ?? multiSelectedClips
        guard let category = MultiPasteComposer.category(of: selected) else { return }
        if let reason = multiPasteBlockReason(for: action, clips: selected) {
            publishMultiPasteBlockedToast(reason)
            return
        }
        let mode: PasteMode = (action == .paste) ? effectivePasteMode : .copyBack
        Logger.ui.info("MultiPaste 실행 — action=\(String(describing: action), privacy: .public) 계열=\(String(describing: category), privacy: .public) 선택=\(selected.count, privacy: .public) mode=\(mode.rawValue, privacy: .public)")

        do {
            switch category {
            case .text:
                let separator = MultiPasteComposer.resolveSeparator(Self.multiPasteSeparatorRaw)
                let joined = MultiPasteComposer.joinedText(clips: selected, separator: separator)
                try await pasteService.pasteJoinedText(joined, mode: mode)
                await registerJoinedTextClip(joined)
                toastQueue?.enqueue(.success, String(
                    format: L10n(action == .paste ? "toast.multiPaste.text.done" : "toast.multiPaste.text.copied"),
                    selected.count
                ))

            case .files:
                let urls = MultiPasteComposer.fileURLs(clips: selected)
                try await pasteService.pasteFileURLs(urls, mode: mode)
                await registerFileBundleClip(from: selected)
                toastQueue?.enqueue(.success, String(
                    format: L10n(action == .paste ? "toast.multiPaste.files.done" : "toast.multiPaste.files.copied"),
                    urls.count
                ))

            case .mixed:
                // 계열별로 모아 두 번에 나눠 붙인다 — 파일·이미지 배열 먼저, 이어서 연결된 텍스트.
                // 선택 순서를 그대로 따르지 않는 이유는 `MultiPasteComposer.sequentialGroups` 주석 참조.
                let groups = MultiPasteComposer.sequentialGroups(clips: selected)
                let separator = MultiPasteComposer.resolveSeparator(Self.multiPasteSeparatorRaw)
                try await pasteService.pasteMixed(
                    fileURLs: MultiPasteComposer.fileURLs(clips: groups.files),
                    joinedText: groups.texts.isEmpty
                        ? nil
                        : MultiPasteComposer.joinedText(clips: groups.texts, separator: separator)
                )
                // 혼합은 산출물이 둘로 갈려 *하나의 클립* 으로 담을 수 없어 **저장하지 않는다**.
                toastQueue?.enqueue(.success, String(format: L10n("toast.multiPaste.mixed.done"), selected.count))
            }
        } catch {
            Logger.ui.error("MultiPaste 실패 — \(error.localizedDescription, privacy: .public)")
            toastQueue?.enqueue(.warn, L10n("toast.multiPaste.failed"))
            // 실패했으면 선택은 남긴다 — 사용자가 다시 시도할 수 있어야 한다.
            return
        }

        clearMultiSelection()
        await reload()
    }

    /// 텍스트 묶음 결과를 새 클립으로 등록한다.
    /// 수집 시점 dedup 정책(V2)상 같은 본문이 이미 있으면 새 row 대신 기존 row 의 `last_used_at` 만 갱신된다 —
    /// 어느 쪽이든 히스토리 최상단에 오므로 사용자가 보는 결과는 같다.
    private func registerJoinedTextClip(_ body: String) async {
        guard !body.isEmpty else { return }
        let now = Date()
        let clip = Clip(
            id: UUID(),
            type: .text,
            body: body,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: now,
            lastUsedAt: now
        )
        do {
            let evicted = try await repository.insert(clip)
            for old in evicted { try? await fileClipService.delete(old) }
            pruneMultiSelection(deletedIds: evicted.map(\.id))
            Logger.ui.info("MultiPaste 새 텍스트 클립 등록 — 길이=\(body.count, privacy: .public)")
        } catch {
            Logger.ui.error("MultiPaste 새 텍스트 클립 등록 실패 — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 파일 묶음 결과를 새 *다중 파일* 클립으로 등록한다.
    ///
    /// 알려진 한계 — 새 클립은 원본 클립들이 쓰던 **같은 파일을 가리킨다**(디스크 카피본을 새로 뜨지 않는다).
    /// 원본 클립을 삭제하면 그 카피본이 지워져 묶음 클립의 해당 항목이 빈 경로가 된다.
    /// 카피본을 복제하면 100MB 급 파일이 선택 횟수만큼 불어나므로 참조를 택했다.
    private func registerFileBundleClip(from clips: [Clip]) async {
        let entries: [ClipFileEntry] = clips.flatMap { clip -> [ClipFileEntry] in
            if clip.isMultiFile, let existing = clip.fileEntries { return existing }
            guard let path = clip.filePath ?? clip.fileOriginalPath else { return [] }
            return [ClipFileEntry(
                originalPath: clip.fileOriginalPath ?? "",
                filePath: path,
                isFileExternal: clip.isFileExternal
            )]
        }
        guard !entries.isEmpty, let json = try? ClipFileEntry.encodeJSON(entries) else {
            Logger.ui.error("MultiPaste 새 파일 클립 등록 실패 — entries 직렬화 불가")
            return
        }
        let now = Date()
        let clip = Clip(
            id: UUID(),
            type: .file,
            body: nil,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: now,
            lastUsedAt: now,
            pinnedAt: nil,
            filePathsJson: json
        )
        do {
            let evicted = try await repository.insert(clip)
            // LRU 로 밀려난 클립의 카피본을 지운다. 단 **이번 묶음이 가리키는 파일은 남긴다** —
            // 위 한계와 같은 이유로 경로를 공유하므로, 그냥 지우면 방금 만든 클립이 곧바로 빈 경로가 된다.
            let keep = Set(entries.map(\.filePath))
            for old in evicted where collectReferencedPaths(from: [old]).isDisjoint(with: keep) {
                try? await fileClipService.delete(old)
            }
            pruneMultiSelection(deletedIds: evicted.map(\.id))
            Logger.ui.info("MultiPaste 새 파일 클립 등록 — 항목=\(entries.count, privacy: .public)")
        } catch {
            Logger.ui.error("MultiPaste 새 파일 클립 등록 실패 — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reload / Search
    func reload() async {
        do {
            let fetched = try await repository.fetchAll()
            clips = fetched
            clampSelection()
            // TASK-055 — 데이터 reload 는 *행 변경의 일종* (정렬 / 삭제 / dedup 후 idx 자리에 다른 clip 가능). close 단일 룰.
            dismissClipDetail()
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
            // TASK-055 — 검색 결과 변동 = 행 변경. selectedIdx didSet 가 이미 0 인 상태에서 = 0 박으면 didSet 미발화 → 명시 dismiss 호출.
            dismissClipDetail()
            // TASK-037 — 검색 결과 변동도 visibleClips 변동. autoFit ON 시 컨테이너 자라남/줄어듦.
            NotificationCenter.default.post(name: Self.displayLayoutDidChange, object: nil)
        } catch {
            Logger.ui.error("ClipsViewModel.performSearch error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// TASK-061 — 검색 디바운스 진입점. plan F-009 `Constants.searchDebounce` (100ms) 정합 구현.
    /// 흐름: 이전 `pendingSearchTask` cancel → 새 Task 박음 → `searchDebounce` 만큼 sleep → cancel 검증 → `performSearch()`.
    /// 호출 site = `SearchBarView.onChange(of: viewModel.searchQuery)` (`.onChange` 매 키 입력마다 발화).
    /// 빠른 타이핑 시 매 호출이 이전 Task cancel → 마지막 호출만 100ms 디바운스 후 실제 DB 검색 → notification 1회 발행 → setFrame 1회.
    func scheduleSearch() {
        pendingSearchTask?.cancel()

        let clock = ContinuousClock()
        let now = clock.now

        // 첫 schedule 시점에 max wait deadline 박음. 이후 호출 시 유지 (사용자 빠른 타이핑 사이클 동안 deadline 보존).
        if searchMaxWaitDeadline == nil {
            searchMaxWaitDeadline = now.advanced(by: Constants.searchMaxWait)
        }
        let debounceDeadline = now.advanced(by: Constants.searchDebounce)
        // debounce vs maxWait 중 *먼저 도달* deadline 박음.
        let effectiveDeadline = min(debounceDeadline, searchMaxWaitDeadline!)

        pendingSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(until: effectiveDeadline, clock: clock)
            guard !Task.isCancelled, let self else { return }
            self.searchMaxWaitDeadline = nil  // 다음 사이클 새 deadline 박힘.
            await self.performSearch()
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
        let raw = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.clipsPerPage)
        return max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, raw))
    }

    /// TASK-037 — 디스플레이 환경설정 변경 시 NotificationCenter 채널. PopoverWindow 가 구독해서 NSPanel frame 동적 재계산.
    /// 트리거: (a) SettingsViewModel.setClipsPerPage/setAutoFitClipListHeight 호출 끝 / (b) reload() 끝 (visibleClips 변동 — autoFit ON 시 의미).
    static let displayLayoutDidChange = Notification.Name("stash.displayLayoutDidChange")

    /// TASK-037 — 클립 리스트 영역 동적 높이 계산 (순수 함수, 인자 명시).
    /// SwiftUI 가 `@AppStorage` 등으로 추적한 값을 호출처에서 전달해야 body 재계산이 트리거됨.
    /// 공식: autoFit ON → `rows = min(visibleCount, N)` / OFF → `rows = N`.
    /// TASK-061 — floor=3 룰 폐기 (사용자 요구). 이전 `rows = max(min(visibleCount, N), min(N, 3))` 가 visibleCount 1-2 케이스에 *3행 강제* → 검색 진행 중 결과 변동 시 사용자 인지 *3행 사이즈로 왔다갔다* oscillation. visibleCount 자연 그대로 변동으로 단순화.
    /// 화면 cap: popover 가 화면 visible 영역 초과 시 cap 적용 (popover top = visible.maxY 까지 박혀 menu bar 바로 아래에 붙음).
    /// TASK-052 — `hintBarVisible` 인자 추가. OFF 시 totalOverhead 에서 `hintBarOverhead` (실측 42pt) 차감 → clipList cap 확장 → 한 행 더 표시 + popover total ON/OFF 동일 (method2 우하단 anchor 시 상단 공백 잔존 차단).
    /// TASK-099 — `previewBarVisible` 인자 추가. 프리뷰 바가 떠 있는 동안은 clipList cap 을 그만큼 줄여
    /// popover 가 화면 밖으로 자라는 것을 막는다. 기본값 false = 기존 호출처 동작 불변.
    static func effectiveClipListHeight(visibleCount: Int, clipsPerPage: Int, autoFit: Bool, hasPinned: Bool, hintBarVisible: Bool, previewBarVisible: Bool = false) -> CGFloat {
        let n = max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, clipsPerPage))
        let rowHeight = DesignTokens.Spacing.rowMinHeight
        let rowGap = DesignTokens.Spacing.rowGap
        let rows: Int
        if autoFit {
            // TASK-061 — visibleCount 자연 그대로 (floor=3 폐기 — 사용자 요구). 1-2 케이스도 자연 변동.
            rows = min(visibleCount, n)
        } else {
            rows = n
        }
        let raw = CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowGap
        // 화면 cap — TASK-057 cappedRowsForCurrentScreen 헬퍼 위임 (windowWillResize raw 동기화 분기와 공유).
        let cappedRows = cappedRowsForCurrentScreen(hasPinned: hasPinned, hintBarVisible: hintBarVisible, previewBarVisible: previewBarVisible)
        let cap = CGFloat(cappedRows) * rowHeight + CGFloat(max(0, cappedRows - 1)) * rowGap
        return min(raw, cap)
    }

    /// TASK-057 — 현재 화면 + UI 상태 기준 *clipList 영역에 들어갈 수 있는 최대 정수 행 수*.
    /// `effectiveClipListHeight` 의 cap 계산 (line 339 자리) + `PopoverWindow.windowWillResize` 의 raw vs effective 동기화 분기 양쪽 공통 진입점.
    /// TASK-054 fix-2 정합 — cap 을 *정수 행 단위 floor* 박음 (fractional 잔여 공간 차단). (rowHeight + rowGap) 단위 floor — gap 1 개 분량 보정 위해 (screenAvailable + rowGap) 사용.
    /// TASK-052 정합 — hintBarVisible=false 시 baseOverhead 에서 hintBarOverhead 차감 (clipList cap 확장).
    /// TASK-099 정합 — `previewBarVisible` 시 프리뷰 바 높이만큼 overhead 를 더해 cap 을 낮춘다.
    static func cappedRowsForCurrentScreen(hasPinned: Bool, hintBarVisible: Bool, previewBarVisible: Bool = false) -> Int {
        let rowHeight = DesignTokens.Spacing.rowMinHeight
        let rowGap = DesignTokens.Spacing.rowGap
        let baseOverhead = DesignTokens.Spacing.clipListOverheadBase
        let pinRowOverhead: CGFloat = hasPinned ? (DesignTokens.Spacing.pinRowHeight + DesignTokens.Spacing.pinRowMarginVert * 2) : 0
        let hintBarAdjust: CGFloat = hintBarVisible ? 0 : DesignTokens.Spacing.hintBarOverhead
        let previewBarOverhead: CGFloat = previewBarVisible ? DesignTokens.Spacing.previewBarOverhead : 0
        let totalOverhead = baseOverhead + pinRowOverhead - hintBarAdjust + previewBarOverhead
        let screenAvailable = (NSScreen.main?.visibleFrame.height ?? 800) - totalOverhead
        return max(1, Int((screenAvailable + rowGap) / (rowHeight + rowGap)))
    }

    /// TASK-077 — autoFit ON 시 popover 높이 cap 계산.
    /// 사용자 요구: popover 사이즈 변경 언제나 가능. autoFit ON + *visibleClips.count 기반 추적 높이* 초과 시도만 차단.
    /// `measured` = 현재 clipsPerPage 기반 SwiftUI body fitting (`measuredFittingHeight`). 이 값에 *추가 행 분량* 더해 cap 산출.
    /// 추가 행 = `min(visibleCount, capRows) - min(visibleCount, clipsPerPage)` — 화면 cap 도달 시 그 안에서 멈춤.
    /// 예시: visibleCount=10, clipsPerPage=6, capRows=15 → currentRows=6, targetRows=10, extraRows=4 → cap = measured + 4*46pt.
    static func computeAutoFitCap(
        measured: CGFloat,
        visibleCount: Int,
        clipsPerPage: Int,
        capRows: Int,
        rowHeight: CGFloat = DesignTokens.Spacing.rowMinHeight,
        rowGap: CGFloat = DesignTokens.Spacing.rowGap
    ) -> CGFloat {
        let currentRowsShown = min(visibleCount, clipsPerPage)
        let targetRowsShown = min(visibleCount, capRows)
        let extraRows = max(0, targetRowsShown - currentRowsShown)
        let snap = rowHeight + rowGap
        return measured + CGFloat(extraRows) * snap
    }

    /// TASK-057 — `PopoverWindow.windowWillResize` 드래그 시 raw `clipsPerPage` 와 화면 cap 정합 보정.
    /// 사용자가 환경설정에서 raw 50 같이 *화면 cap 초과* 설정한 상태에서 popover 테두리 드래그로 축소 시도 → 시각 상 보이는 클립 수 (effective = capRows) 기준 ±1 진행이 사용자 인식과 정합.
    /// 분기:
    /// - `signDelta < 0 && current > capRows` (raw>cap 축소): `newRaw = max(min, capRows + signDelta)` (raw jump 동기화 + 축소).
    /// - else (cap 미달 또는 늘림): `newRaw = max(min, min(max, current + signDelta))` (정상 ±1 + clamp).
    static func resolveNewClipsPerPageForResize(current: Int, signDelta: Int, capRows: Int) -> Int {
        if signDelta < 0 && current > capRows {
            return max(Constants.clipsPerPageMin, capRows + signDelta)
        } else {
            return max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, current + signDelta))
        }
    }

    /// TASK-078 — `PopoverWindow.windowWillResize` 의 estimatedHeight 분기 *visual delta* 계산 (순수 함수, NSWindow 의존 X — 단위 테스트 진입점).
    /// 사용자 인식 = *1 행 단위 시각 변화*. raw 변화량 (`newRaw - current`) 과 별개.
    /// TASK-057 의도 (raw>cap 축소 jump 시 1 행 시각 축소) + TASK-071 Phase 7 의도 (min/max cap 도달 시 frame 유지) 동시 정합.
    /// 분기:
    /// - `newRaw == current` (min/max cap 도달 — `resolveNewClipsPerPageForResize` clamp 결과 변동 X): `0` 반환 → estimatedHeight 유지 (시스템 표준 minSize/maxSize 도달 패턴).
    /// - else: `signDelta` 반환 → 사용자 인식 ±signDelta 행 시각 변화 (raw>cap 축소 jump 케이스 포함 — newRaw 가 capRows-1 로 jump 동기화 박혀도 시각상 1 행 축소가 사용자 인식 정합).
    /// 회귀 fix 배경: TASK-071 Phase 7 이 estimatedHeight 를 `(newRaw - current) * snap` 박은 후 raw>cap 축소 jump 케이스 (예: current=50, newRaw=25, signDelta=-1) 에서 estimatedHeight = current_frame + (-25) * 46 = *너무 작은 값* (음수 가능) → NSWindow contentMinSize 박혀 frame 안 줄어듦 → 사용자 들썩거림 회귀. visual delta 분리로 TASK-057 의도 복원.
    static func resolveVisualResizeDelta(current: Int, newRaw: Int, signDelta: Int) -> Int {
        return (newRaw == current) ? 0 : signDelta
    }

    /// TASK-037 — UserDefaults 직접 조회 wrapper. SwiftUI 외부 호출용.
    /// TASK-052 — `hintBarVisible` UserDefaults 조회 추가 (default true — 사용자 미설정 시 시각 ON 유지).
    static func effectiveClipListHeightFromUserDefaults(visibleCount: Int, hasPinned: Bool) -> CGFloat {
        let n = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.clipsPerPage)
        let autoFit = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoFitClipListHeight)
        let hintBarVisible: Bool = (UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hintBarVisible) as? Bool) ?? true
        return effectiveClipListHeight(visibleCount: visibleCount, clipsPerPage: n, autoFit: autoFit, hasPinned: hasPinned, hintBarVisible: hintBarVisible)
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
        // TASK-099 — 다중 선택은 popover 한 번 열린 동안만 유효하다. 새로 열면 빈 상태에서 시작.
        clearMultiSelection()
        ignoreHoverUntil = Date().addingTimeInterval(DesignTokens.Animation.popoverOpenHoverIgnoreDelay)
        // TASK-027 / TASK-055 — popover 새 호출 시 detail panel 강제 닫음 (default closed). frame .zero 초기화 동반.
        activeRowFrameInPopover = .zero
        dismissClipDetail()
        // TASK-061 — popover 재진입 시 이전 검색 디바운스 잔존 Task cancel + max wait deadline reset 안전망. 잔존 시 새 popover 진입 후 이전 검색 결과로 clips 덮어쓰기 race 차단.
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        searchMaxWaitDeadline = nil
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
        // TASK-033 매트릭스는 `effectivePasteMode` 단일 소스 (TASK-099 fix-4 정리 — 묶음 경로가 같은 판정을
        // 따로 계산하고 있어 한쪽만 고치면 단일/묶음이 갈리는 자리였다).
        let effectiveMode = effectivePasteMode
        do {
            try await pasteService.paste(clip: clip, mode: effectiveMode)
            publishPasteToast(for: clip, mode: effectiveMode)
        } catch {
            Logger.ui.error("ClipsViewModel.paste error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishPasteToast(for clip: Clip, mode: PasteMode) {
        guard let toastQueue else { return }
        if mode == .autoPaste {
            // TASK-066 — snippet suffix 제거, 본문 단순화 *"붙여넣기됨"*.
            toastQueue.enqueue(.success, L10n("toast.paste.done"))
        } else {
            // TASK-033 — *바로 붙여넣기* OFF 또는 권한 X 상태 popover 클립 선택 시 단축키 안내 없는 단순 토스트 (UX-UI §6 알림 표 정합).
            toastQueue.enqueue(.success, L10n("toast.copy.done"))
        }
    }

    /// TASK-024 — ⌘+C 복사 단축키 액션. Settings `pasteMode` 라디오 무관 *항상* `.copyBack` 모드 호출 — 클립보드 갱신만, ⌘V 합성 X. Accessibility 권한 무관 항상 활성. zone == .pin / .clip 분기는 paste(at:zone:) 와 동일.
    /// TASK-028 — `zone` 명시 파라미터화. paste(at:zone:) 와 동일 사유. zone 분기 + 가드는 `clipForZone(at:zone:)` 로 분리.
    func copy(at idx: Int, zone: FocusZone) async {
        guard let clip = clipForZone(at: idx, zone: zone) else { return }
        Logger.ui.info("Copy invoked — zone=\(zone.rawValue, privacy: .public) idx=\(idx, privacy: .public) clipId=\(clip.id.uuidString, privacy: .public) type=\(clip.type.rawValue, privacy: .public)")
        do {
            try await pasteService.paste(clip: clip, mode: .copyBack)
            publishCopyToast()
        } catch {
            Logger.ui.error("ClipsViewModel.copy error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishCopyToast() {
        guard let toastQueue else { return }
        toastQueue.enqueue(.success, L10n("toast.copy.done"))
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
            Logger.ui.warning("핀 한도 초과 — 토스트 발행 (max=\(Constants.maxPinnedClips, privacy: .public))")
            // TASK-066 — 키 dotted rename + Constants 동적 + ttl 자동 추종.
            let body = String(format: L10n("toast.pin.limit"), Constants.maxPinnedClips)
            toastQueue?.enqueue(.warn, body)
        } catch {
            Logger.ui.error("ClipsViewModel.togglePin error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// TASK-098 — 설정 PIN 단축키 행의 *핀 해제*.
    ///
    /// 클립 자체는 지우지 않는다 — `is_pinned` 만 내리므로 항목은 히스토리에 남는다. 값(`body`) 수정도 그대로 유지된다.
    /// 반면 **명칭(`pin_alias`)은 초기화된다** — 핀에만 있는 개념이라 재고정 시 옛 이름이 되살아나면 안 된다(`togglePin` 이 처리).
    /// 해제한 *그 자리만* 비고 다른 핀의 번호·조합은 그대로 유지된다 (자리를 `pin_slot` 데이터로 갖는 구조).
    ///
    /// `trackSelection: .pin` 을 넘기는 이유 — 그 분기가 *핀 목록이 줄었을 때의 후처리*(선택 idx clamp + **마지막 핀 해제 시 사이드바 닫기**)를
    /// 담당한다. 설정 창에서 해제했다고 그 후처리를 건너뛰면 popover 사이드바가 **빈 채로 남는다**.
    /// (파라미터 이름이 호출 위치가 아니라 *어느 목록을 추적하는가* 를 뜻한다는 점에 주의.)
    func unpinFromSettings(id: UUID) async {
        Logger.ui.info("unpinFromSettings — id: \(id.uuidString, privacy: .public)")
        await togglePin(id: id, trackSelection: .pin)
    }

    /// TASK-098 — 핀 표시용 명칭 저장. 설정 PIN 단축키 행의 명칭 필드 확정 시 호출.
    /// 입력 정규화(공백 제거 · 빈 문자 → 해제 · 40자 상한)는 `PinPasteShortcutResolver.normalizeAlias` 단일 지점.
    func setPinAlias(id: UUID, rawAlias: String?) async {
        let normalized = PinPasteShortcutResolver.normalizeAlias(rawAlias)
        do {
            try await repository.setPinAlias(id: id, alias: normalized)
            Logger.ui.info("setPinAlias — id: \(id.uuidString, privacy: .public) 설정: \(normalized != nil, privacy: .public) 길이: \(normalized?.count ?? 0, privacy: .public)")
            await reload()
        } catch {
            Logger.ui.error("ClipsViewModel.setPinAlias error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// TASK-098 — 클립 본문 수정. 설정 PIN 단축키 행의 값 편집 확정 시 호출.
    /// 텍스트 타입만 · 빈 값 거부(기존 값 유지) · `last_used_at` 미갱신은 repository 가 최종 판정한다.
    /// - Returns: 반영됐으면 true. false 면 호출자가 편집 전 값으로 되돌린다.
    @discardableResult
    func updateClipBody(id: UUID, rawBody: String?) async -> Bool {
        guard let value = PinPasteShortcutResolver.normalizeValue(rawBody) else {
            Logger.ui.info("updateClipBody 거부 — id: \(id.uuidString, privacy: .public) 사유: 빈 값 (수정 전 값 유지)")
            return false
        }
        do {
            let applied = try await repository.updateBody(id: id, body: value)
            Logger.ui.info("updateClipBody — id: \(id.uuidString, privacy: .public) 반영: \(applied, privacy: .public) 길이: \(value.count, privacy: .public)")
            if applied { await reload() }
            return applied
        } catch {
            Logger.ui.error("ClipsViewModel.updateClipBody error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// TASK-098 fix-3 — 설정 PIN 단축키 행의 *빈 순번* 에 값을 입력해 확정하면 새 핀을 만든다.
    ///
    /// 주의: 수집 시점 dedup 정책(V2)상 동일 `(type:text, body)` 가 이미 있으면 새 row 가 생기지 않고
    /// 기존 row 의 `last_used_at` 만 갱신된다. 그래서 insert 후 *해당 body 의 row 를 다시 찾아* 핀 처리한다
    /// (새로 생긴 row 든 기존 row 든 같은 경로로 수습).
    /// - Parameter slot: 사용자가 클릭한 *자리 번호*. 그 자리에 그대로 꽂는다 (TASK-098 검수 정정).
    ///   nil 이면 가장 낮은 빈 자리(`togglePin` 기본 규칙).
    /// - Returns: 핀이 만들어졌으면 true. 값이 비었거나 자리가 없으면 false.
    @discardableResult
    func createPinnedClip(body rawBody: String, alias rawAlias: String?, slot: Int? = nil) async -> Bool {
        guard let value = PinPasteShortcutResolver.normalizeValue(rawBody) else {
            Logger.ui.info("createPinnedClip 거부 — 사유: 빈 값")
            return false
        }
        // 자리를 **먼저 확정한다** — 요청 자리가 유효하고 비어 있으면 그대로, 아니면 가장 낮은 빈 자리.
        // (핀인데 자리가 NULL 인 row 를 만들지 않기 위해 insert 전에 값을 정한다.)
        let occupied = pinnedClips.map(\.pinSlot)
        let taken = Set(occupied.compactMap { $0 })
        let requested = slot.flatMap { s in (1...Constants.maxPinnedClips).contains(s) && !taken.contains(s) ? s : nil }
        // 개수 가드도 함께 둔다 — 이 경로는 `insert` 로 핀 row 를 직접 만들어 `togglePin` 의 한도 검사를 거치지 않는다.
        // 자리 검사만 두면 *자리 없는 핀* (V7 이전 데이터 등)이 섞였을 때 한도를 넘겨 만들 수 있다.
        guard pinnedClips.count < Constants.maxPinnedClips,
              let targetSlot = requested ?? PinPasteShortcutResolver.lowestFreeSlot(occupied: occupied) else {
            Logger.ui.warning("createPinnedClip 거부 — 빈 자리 없음 (max=\(Constants.maxPinnedClips, privacy: .public))")
            toastQueue?.enqueue(.warn, String(format: L10n("toast.pin.limit"), Constants.maxPinnedClips))
            return false
        }
        let now = Date()
        let draft = Clip(
            id: UUID(),
            type: .text,
            body: value,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: true,
            createdAt: now,
            lastUsedAt: now,
            pinnedAt: now,
            pinAlias: PinPasteShortcutResolver.normalizeAlias(rawAlias),
            pinSlot: targetSlot
        )
        do {
            _ = try await repository.insert(draft)
            await reload()
            guard let target = clips.first(where: { $0.type == .text && $0.body == value }) else {
                Logger.ui.error("createPinnedClip — insert 후 대상 row 조회 실패")
                return false
            }
            if target.id != draft.id {
                // dedup 으로 **기존 row 가 재사용된** 경로.
                // 그 row 가 이미 핀이면 실패로 돌려준다 — 자리를 옮기면 사용자가 만든 배치가 흔들리고,
                // 조용히 성공을 반환하면 요청한 자리는 빈 채로 남는데 *다른 자리 핀의 명칭만* 바뀌어 엉뚱한 행이 변한다.
                // 어느 번호에 이미 있는지는 호출자(설정 창)가 안내한다.
                guard !target.isPinned else {
                    Logger.ui.info("createPinnedClip 거부 — 같은 본문이 이미 \(target.pinSlot?.description ?? "?", privacy: .public)번 자리에 고정됨 (요청 자리: \(targetSlot, privacy: .public))")
                    return false
                }
                // 핀이 아닌 기존 row 를 그대로 승격 — 핀·자리가 안 붙어 있으므로 여기서 채운다.
                if try await repository.pinAtSlot(id: target.id, slot: targetSlot) == false {
                    Logger.ui.warning("createPinnedClip — \(targetSlot, privacy: .public)번 자리 배정 실패 → 빈 자리 배정으로 대체")
                    try await repository.togglePin(id: target.id)
                }
            }
            // (target.id == draft.id 면 새 row 가 그대로 들어간 것 — insert 시점에 핀·자리가 이미 박혀 있다.)
            if let alias = PinPasteShortcutResolver.normalizeAlias(rawAlias), target.pinAlias != alias {
                try await repository.setPinAlias(id: target.id, alias: alias)
            }
            await reload()
            onPinnedClipsChange?()
            Logger.ui.info("createPinnedClip — id: \(target.id.uuidString, privacy: .public) 길이: \(value.count, privacy: .public) 명칭: \(rawAlias?.isEmpty == false, privacy: .public)")
            return true
        } catch DatabaseError.pinLimitReached {
            Logger.ui.warning("createPinnedClip — 핀 한도 초과 (repository)")
            toastQueue?.enqueue(.warn, String(format: L10n("toast.pin.limit"), Constants.maxPinnedClips))
            return false
        } catch {
            Logger.ui.error("ClipsViewModel.createPinnedClip error: \(error.localizedDescription, privacy: .public)")
            return false
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
        // TASK-099 — 사라진 클립이 선택에 남아 있으면 묶음 실행이 유령 항목을 붙이려 든다.
        pruneMultiSelection(deletedIds: [clip.id])
        await reload()
        clampSelection()
    }

    /// TASK-034 — DB 삭제 + entry 별 디스크 cleanup + 핀 참조 외 clips/ 폴더 sweep (누적 고아 + 디스크 삭제 실패 fallback 회수).
    func deleteAllExceptPinned() async {
        let deleted = (try? await repository.deleteAllExceptPinned()) ?? []
        for clip in deleted {
            try? await fileClipService.delete(clip)
        }
        // TASK-099 — 전체 삭제로 사라진 클립을 선택에서 걷어낸다 (핀은 남으므로 선택이 전부 비지는 않을 수 있다).
        pruneMultiSelection(deletedIds: deleted.map(\.id))
        let pinnedPaths = collectReferencedPaths(from: pinnedClips)
        await fileClipService.sweepOrphans(referencedPaths: pinnedPaths)
        await reload()
        selectedIdx = 0
        // TASK-066 — kind .info → .success, ttl 자동 추종.
        toastQueue?.enqueue(.success, L10n("toast.deleteAll.done"))
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
        // TASK-062 — 영역 합집합 가드. `PopoverWindow` 가 NSEvent.mouseLocation + 핀 사이드바 frame + 상세 sub-panel frame 합집합 검사 후 bool 반환 — true 면 합집합 안 (close 차단, TASK-030 자식 sub-panel 보호 의도 보존) / false 또는 nil 면 합집합 밖 (close 진행 + `pinSidebarOpen=false` didSet 의 TASK-055 단일 룰로 상세 sub-panel 동반 close). 기존 `isDetailPanelOpen` boolean 가드 대체.
        if shouldRetainPinSidebarOnHoverExit?() == true { return }
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

    // MARK: - Clip Detail sub-window (TASK-027 / TASK-055)

    /// TASK-055 — 사용자 명시 트리거 (⌘+D 단축키 / hover 임계 도달) 진입점.
    /// 이미 표시 중이면 toggle close. 아니면 활성 클립 + Provider 매칭 검증 후 ClipDetailRequest emit.
    /// 매칭 X / frame 미게시 시 no-op.
    func triggerClipDetail() {
        if clipDetailVisible {
            dismissClipDetail()
            return
        }
        emitClipDetailRequestIfMatching()
    }

    /// TASK-055 — 명시 close 진입점. detail panel hide + clipDetailVisible=false + hover task cancel.
    /// 호출 site = popover hide / 행 변경 didSet / popover 재호출 (resetForOpen) / triggerClipDetail toggle close 분기.
    func dismissClipDetail() {
        hoverDetailTask?.cancel()
        hoverDetailTask = nil
        hoverDetailTaskRowId = nil
        if clipDetailVisible {
            clipDetailVisible = false
            Logger.ui.debug("ClipDetail: dismiss")
        }
        onShowClipDetailChange?(nil)
        lastEmittedClipId = nil
    }

    /// TASK-055 — 활성 클립 + Provider 매칭 + frame 게시 검증 후 ClipDetailRequest emit.
    /// 호출 site = `triggerClipDetail` (트리거 발화) / `activeRowFrameInPopover` didSet (이미 표시 중 frame 재계산).
    /// 매칭 실패 (활성 행 없음 / Provider 없음) → `dismissClipDetail()` 호출로 통합 (hover task cancel 동반은 의도된 부수효과 — 활성 행 없는데 hover task 잔존할 이유 X).
    private func emitClipDetailRequestIfMatching() {
        guard let active = activeClipForDetail(),
              ClipDetailRegistry.provider(for: active.clip) != nil else {
            dismissClipDetail()
            return
        }
        guard activeRowFrameInPopover != .zero else {
            // frame 미게시 — SwiftUI GeometryReader 게시 후 didSet 가 재호출.
            return
        }
        let req = ClipDetailRequest(
            clip: active.clip,
            zone: active.zone,
            rowFrameInPopover: activeRowFrameInPopover
        )
        Logger.ui.debug("ClipDetail: emit — clipId=\(active.clip.id.uuidString, privacy: .public) zone=\(String(describing: active.zone), privacy: .public)")
        clipDetailVisible = true
        lastEmittedClipId = active.clip.id
        onShowClipDetailChange?(req)
    }

    /// TASK-055 — 클립 행 hover 진입. 같은 row.id 추적 중이면 task 보존 (미세 움직임 누적). 다른 row.id 시 cancel + 새 task 시작.
    /// 임계 도달 시 `triggerClipDetail()` 자동 발화 — 활성 행이 hover 행과 일치 + Provider 매칭이면 detail emit.
    func hoverEnterRow(id: UUID) {
        if isHoverIgnored { return }
        if hoverDetailTaskRowId == id, hoverDetailTask != nil {
            return  // 미세 움직임 누적 보존
        }
        hoverDetailTask?.cancel()
        hoverDetailTaskRowId = id
        hoverDetailTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Constants.clipDetailHoverDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // 임계 도달 시 현재 추적 row.id 가 여전히 같은 id 인지 검증 후 trigger.
            guard self.hoverDetailTaskRowId == id else { return }
            self.hoverDetailTask = nil
            self.hoverDetailTaskRowId = nil
            self.triggerClipDetail()
        }
    }

    /// TASK-055 — 같은 row.id exit 시 task cancel. 다른 row.id exit 은 hoverEnterRow 안에서 이미 cancel 처리되므로 no-op.
    func hoverExitRow(id: UUID) {
        guard hoverDetailTaskRowId == id else { return }
        hoverDetailTask?.cancel()
        hoverDetailTask = nil
        hoverDetailTaskRowId = nil
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
