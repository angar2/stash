// Settings 4탭 ViewModel — Login Item 토글 / 바로 붙여넣기 토글 / 저장하지 않을 앱 / 데이터 폴더 액션 + 환경설정 윈도우 내부 토스트 시스템 + 단축키 검증·되돌리기 (TASK-033 정합)
import Foundation
import Observation
import AppKit
import OSLog
import KeyboardShortcuts

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - State
    var loginItemEnabled: Bool = false
    /// TASK-033 — 기존 `pasteMode: PasteMode` 라디오 폐기 → 단일 boolean 토글로 단순화. true = auto-paste / false = copy back. 권한 X 시 토글 disabled.
    var autoPasteEnabled: Bool = true
    var blockedAppBundleIds: [String] = []
    var shortcutConflictMessage: String?
    /// PermissionService.statusPublisher 구독으로 Composition Root 가 갱신.
    var accessibilityGranted: Bool = false
    /// TASK-102 — 자동 업데이트 창구. Composition Root 가 주입한다.
    /// 관찰 대상이어야 확인 상태(*확인 중…* / *최신 버전입니다*)가 정보 탭에 즉시 반영된다.
    private(set) var updateService: UpdateService?

    // MARK: - Display tab (TASK-037)
    /// 한 페이지에 보여줄 클립 개수. 1~30 clamp. default 6.
    /// 변경 시 UserDefaults 동기화 + ClipsViewModel.effectivePageSize() 가 매 호출 시점 최신값 조회 + popover 가 @AppStorage 또는 Observation 으로 즉시 재렌더.
    var clipsPerPage: Int = Constants.clipsPerPageDefault
    /// 클립 리스트 컨테이너 높이 자동 조정 체크박스. ON 시 컨테이너 행 수 = `max(min(visibleCount, N), min(N, 3))`. default false.
    var autoFitClipListHeight: Bool = false
    /// TASK-052 — popover 하단 `KeyboardHintsView` 표시 여부. default true. OFF 시 힌트바 (상단 Divider 포함) 전체 비표시 + popover height 자동 축소.
    var hintBarVisible: Bool = true
    /// TASK-053 — 앱 강조 색상 모드. `.default` (stash 자체 `#0D6FFF`) / `.system` (`Color.accentColor` macOS 시스템 추종). UX-UI §4-3 *콘텐츠 색상* 라디오 분기 진실 소스.
    var accentColorMode: AccentColorMode = .default
    /// TASK-054 — 방식 2 popover 진입 anchor. 사용자 환경설정 *기본 오픈 위치* 5종. UX-UI §4-3 단일 진실.
    /// `popoverRememberLastPosition == false` 시 매 오픈마다 본 anchor 진입. `== true` 시 저장 좌표 우선 + 화면 밖 fallback 시 본 anchor.
    var popoverDefaultAnchor: PopoverAnchor = .default
    /// TASK-054 — 방식 2 popover *이전 위치 기억하기* 토글. default OFF. ON 시 `panel.hide()` 시점 `frame.origin` UserDefaults 영속 → 다음 오픈 시 복원.
    var popoverRememberLastPosition: Bool = false
    /// TASK-073 — 앱 사용자 표시 언어 (한국어 / 영어). UserDefaults `appLanguage` 영속 — OS 시스템 언어와 무관 고정. 첫 런칭 시 systemDefault (한국어 OS → `.korean` / 그 외 → `.english`) 박힘.
    var appLanguage: AppLanguage = .korean

    /// TASK-033 — 환경설정 윈도우 내부 토스트 큐 (popover 토스트와 별개 시스템). Login Item 실패 / 권한 변동 / 단축키 modifier 검증 / 충돌 검사 토스트 발행 채널.
    let settingsToast: ToastQueue = ToastQueue()

    private let loginItemService: LoginItemService
    /// TASK-100 — 보관 한도 판정에 필요한 *핀 제외 개수* 조회용. 단위 테스트는 주입하지 않는다(옵셔널).
    private let repository: (any ClipRepository)?
    /// TASK-033 fix-2 — 7항목 (popoverOpen + 6종) 변경 revert 용 마지막 valid 단축키 추적.
    private var lastValidPopoverShortcuts: [PopoverShortcutID: PopoverShortcut] = [:]
    /// TASK-033 — revert 호출 재진입 가드.
    private var isRevertingShortcut: Bool = false

    init(loginItemService: LoginItemService, repository: (any ClipRepository)? = nil) {
        self.loginItemService = loginItemService
        self.repository = repository
        self.loginItemEnabled = (try? loginItemService.isEnabled) ?? false
        loadAutoPasteEnabled()
        loadBlockedApps()
        loadDisplayPreferences()
        // TASK-033 fix-2 — 초기 lastValid 채우기.
        for id in PopoverShortcutID.allCases {
            if let shortcut = PopoverShortcutStore.get(id) {
                lastValidPopoverShortcuts[id] = shortcut
            }
        }
        // TASK-054 fix-1 — `clipsPerPageDeltaRequest` notification 구독 폐기. PopoverWindow 가 SettingsViewModel.setClipsPerPage 직접 호출 (시스템 표준 NSWindow resize 위임).
    }

    /// TASK-033 — 권한 변동 감지 (Composition Root가 `PermissionService.statusPublisher` 구독해 호출).
    /// O→X 회수 시: 자동 paste 토글 강제 OFF + 토스트 발행. X→O 부여 시: autoPasteEnabled 자동 ON (TASK-047 — FEATURES.md §541 *"권한 부여 시점에 auto-paste 모드로 자동 복귀"* 정합) + 토스트 1회 발행 (UX-UI §6-1 *"stash가 활성화되었어요"* 정합).
    func updateAccessibilityGranted(_ granted: Bool) {
        let prev = self.accessibilityGranted
        self.accessibilityGranted = granted
        guard prev != granted else { return }
        Logger.ui.info("SettingsViewModel.accessibilityGranted → \(granted, privacy: .public)")
        if !prev && granted {
            // TASK-047 — 회수 분기 `if autoPasteEnabled` 가드와 대칭. 이미 true 면 UserDefaults 쓰기 + 로그 skip (멱등 가드).
            // TASK-066 — 설정 윈도우 토스트 발화 제거. autoPasteEnabled 자동 ON 흐름은 보존 (popover 토스트는 PermissionToastNotifier 가 별도 발화).
            if !autoPasteEnabled {
                autoPasteEnabled = true
                UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
                Logger.ui.info("Permission granted — autoPasteEnabled auto-ON")
            }
        } else if prev && !granted {
            // TASK-066 — 설정 윈도우 토스트 발화 제거. autoPasteEnabled 자동 OFF 흐름은 보존.
            if autoPasteEnabled {
                autoPasteEnabled = false
                UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
                Logger.ui.info("Permission revoked — autoPasteEnabled forced OFF")
            }
        }
    }

    // MARK: - Login Item
    func toggleLoginItem(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            loginItemEnabled = enabled
            Logger.ui.info("LoginItem toggled: \(enabled, privacy: .public)")
        } catch {
            Logger.ui.error("LoginItem toggle failed: \(error.localizedDescription, privacy: .public)")
            // TASK-033 — 실패 토스트 + OFF 원복 (스위치 자동 OFF)
            loginItemEnabled = false
            settingsToast.enqueue(.error, L10n("toast.loginItem.failed"))
        }
    }

    // MARK: - Auto-paste (TASK-033)
    func setAutoPasteEnabled(_ enabled: Bool) {
        // 권한 X 시 ON 시도 차단 (UI에서 disabled 처리하지만 안전망)
        if enabled && !accessibilityGranted {
            Logger.ui.warning("setAutoPasteEnabled(true) blocked — accessibility not granted")
            return
        }
        autoPasteEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
        Logger.ui.info("autoPasteEnabled set: \(enabled, privacy: .public)")
    }

    private func loadAutoPasteEnabled() {
        // TASK-033 — 마이그레이션. 기존 "pasteMode" 키 잔존값 (PasteMode.rawValue) → boolean 변환 + 기존 키 제거.
        if let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.Deprecated.pasteMode) {
            let migrated = (raw == "autoPaste")
            UserDefaults.standard.set(migrated, forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.Deprecated.pasteMode)
            autoPasteEnabled = migrated
            Logger.ui.info("Migrated pasteMode -> autoPasteEnabled: \(migrated, privacy: .public)")
            return
        }
        // default = true (자동 paste 기본 ON — 권한 부여 후 자연 활성)
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.autoPasteEnabled) != nil {
            autoPasteEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
        }
    }

    // MARK: - Display preferences (TASK-037)

    /// 한 페이지 클립 수 변경. 1~30 clamp + UserDefaults 갱신 + state 갱신 (Observation 트리거) + NSPanel frame 재계산 알림.
    func setClipsPerPage(_ value: Int) {
        let clamped = max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, value))
        clipsPerPage = clamped
        UserDefaults.standard.set(clamped, forKey: Constants.UserDefaultsKeys.clipsPerPage)
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
        Logger.ui.info("clipsPerPage set: \(clamped, privacy: .public)")
    }

    /// 높이 자동 조정 체크박스 토글. UserDefaults 갱신 + state 갱신 + NSPanel frame 재계산 알림.
    func setAutoFitClipListHeight(_ value: Bool) {
        autoFitClipListHeight = value
        UserDefaults.standard.set(value, forKey: Constants.UserDefaultsKeys.autoFitClipListHeight)
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
        Logger.ui.info("autoFitClipListHeight set: \(value, privacy: .public)")
    }

    /// TASK-052 — 단축키 설명 표시 체크박스 토글. UserDefaults 갱신 + state 갱신 + NSPanel frame 재계산 알림.
    /// `HistoryPopover` 가 `@AppStorage("hintBarVisible")` 로 동일 키 추적 → SwiftUI body 즉시 재계산 (KeyboardHintsView if 분기), `displayLayoutDidChange` notification 으로 `PopoverWindow._performRefreshFrame` 가 fittingSize 재측정 후 NSPanel.setFrame.
    func setHintBarVisible(_ value: Bool) {
        hintBarVisible = value
        UserDefaults.standard.set(value, forKey: Constants.UserDefaultsKeys.hintBarVisible)
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
        Logger.ui.info("hintBarVisible set: \(value, privacy: .public)")
    }

    /// TASK-053 — 콘텐츠 색상 라디오. UserDefaults 갱신 + state 갱신.
    /// 강조 view 들이 `@AppStorage(AccentColorMode.userDefaultsKey)` 박고 body sentinel 로 SwiftUI 의존성 등록 — UserDefaults 변경 시 자동 body 재평가.
    func setAccentColorMode(_ mode: AccentColorMode) {
        accentColorMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: AccentColorMode.userDefaultsKey)
        Logger.ui.info("accentColorMode set: \(mode.rawValue, privacy: .public)")
    }

    /// TASK-073 — 앱 사용자 표시 언어 라디오. `AppLanguageService.apply` 호출 → UserDefaults + AppleLanguages override + Notification 발행.
    /// SwiftUI 영역은 `@AppStorage(AppLanguage.userDefaultsKey)` 의존성 등록으로 body 자동 재평가. AppKit 영역 (StatusItemController NSMenu) 은 Notification 구독 매뉴얼 재구성.
    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        AppLanguageService.apply(language)
    }

    /// TASK-054 — 방식 2 popover 진입 anchor 설정. UserDefaults raw 직렬화 + state 갱신.
    /// NotificationCenter post X — *다음 오픈 시 적용* 정책 (이미 떠 있는 popover frame 즉시 갱신 불필요).
    func setPopoverDefaultAnchor(_ anchor: PopoverAnchor) {
        popoverDefaultAnchor = anchor
        UserDefaults.standard.set(anchor.rawValue, forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor)
        Logger.ui.info("popoverDefaultAnchor set: \(anchor.rawValue, privacy: .public)")
    }

    /// TASK-054 — *이전 위치 기억하기* 토글. UserDefaults bool + state 갱신.
    /// OFF→ON 직후 저장값 없음 → 다음 오픈은 기본 anchor 진입, 닫힐 때 저장. ON→OFF 시 UserDefaults 저장 좌표 키 제거 (영구 좌표 정합 — 다시 ON 시점에 stale 좌표 진입 차단).
    func setPopoverRememberLastPosition(_ value: Bool) {
        popoverRememberLastPosition = value
        UserDefaults.standard.set(value, forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition)
        if !value {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverLastPositionX)
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverLastPositionY)
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverLastPositionScreenId)
        }
        Logger.ui.info("popoverRememberLastPosition set: \(value, privacy: .public)")
    }

    private func loadDisplayPreferences() {
        // register defaults 가 StashApp 진입점에서 박혔으므로 integer/bool 조회 시 default 값 (6 / false / true) 자연 반환.
        // 단, 사용자가 잘못된 값 (음수 / 30 초과) 박은 케이스 방어 — clamp.
        let rawN = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.clipsPerPage)
        clipsPerPage = max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, rawN))
        autoFitClipListHeight = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoFitClipListHeight)
        // TASK-052 fix — register defaults 의존 폐기 + `loadAutoPasteEnabled` 패턴 정합 (`object(forKey:) != nil` 분기). default true 는 stored property 초기값 으로 보존 — 사용자가 toggle 한 적 없으면 시각 ON 유지.
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hintBarVisible) != nil {
            hintBarVisible = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.hintBarVisible)
        }
        // TASK-053 — 콘텐츠 색상 모드. `AccentColorMode.current` 가 키 없음/잘못된 값 자연 `.default` 반환.
        accentColorMode = AccentColorMode.current
        // TASK-054 — popover 진입 위치 (보관함 오픈 위치). raw 잘못된 값 / 미설정 → `.default` (.bottomRight) fallback.
        if let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor),
           let anchor = PopoverAnchor(rawValue: raw) {
            popoverDefaultAnchor = anchor
        }
        popoverRememberLastPosition = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition)
        // TASK-073 — 앱 사용자 표시 언어. `AppLanguage.current` 가 키 부재/잘못된 값 → systemDefault fallback.
        appLanguage = AppLanguage.current
        // TASK-100 — 보관 한도. clamp · 기본값 fallback 은 `Constants.maxUnpinnedClips` 가 단일 지점에서 처리한다.
        maxUnpinnedClips = Constants.maxUnpinnedClips
        Logger.ui.info("loadDisplayPreferences — clipsPerPage=\(self.clipsPerPage, privacy: .public) autoFit=\(self.autoFitClipListHeight, privacy: .public) hintBarVisible=\(self.hintBarVisible, privacy: .public) accentColorMode=\(self.accentColorMode.rawValue, privacy: .public) popoverAnchor=\(self.popoverDefaultAnchor.rawValue, privacy: .public) rememberLast=\(self.popoverRememberLastPosition, privacy: .public) appLanguage=\(self.appLanguage.rawValue, privacy: .public)")
    }

    /// TASK-033 — 일반 탭 *"시스템 접근 권한"* 링크 클릭 핸들러. macOS 시스템 설정 Accessibility 화면 직접 열기.
    func openSystemSettingsForAccessibility() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 보관 한도 (TASK-100)

    /// 일반 탭 히스토리 한도 입력란의 현재 값.
    ///
    /// TASK-100 이전에는 `Constants.maxUnpinnedClips` 를 그대로 읽는 계산 프로퍼티였다. 저장 상태로 바꾼 이유는
    /// `Constants` 가 UserDefaults 를 읽는 계산 프로퍼티라 Observation 이 변경을 추적하지 못하기 때문이다 —
    /// 값을 바꿔도 화면이 갱신되지 않는다. `clipsPerPage` 와 같은 패턴이다.
    ///
    /// 여기 초기값은 자리만 잡는다 — 실제 값은 init 의 `loadDisplayPreferences()` 가 저장소에서 읽어 덮는다
    /// (초기값으로 저장값을 읽어두면 진실 소스가 둘로 보인다).
    var maxUnpinnedClips: Int = Constants.maxUnpinnedClipsDefault

    /// 보관 한도 확정. 판정은 `HistoryLimitPolicy` 가 하고 여기서는 저장 · 토스트 · 표시값만 다룬다.
    ///
    /// 개수를 캐시하지 않고 매번 조회하는 이유 — 캐시가 실제보다 적으면 현재 보관 개수보다 낮은 한도가
    /// 저장되고, 그 다음 insert 가 LRU 정리로 클립을 지운다. 조회 비용(COUNT 한 번)보다 그 위험이 크다.
    /// - Returns: 입력란에 표시할 값 (수용값 / 되돌릴 현재 개수 / 직전 값).
    @discardableResult
    func commitMaxUnpinnedClips(_ input: String) async -> Int {
        let count = await currentUnpinnedCount()
        switch HistoryLimitPolicy.resolve(input: input, currentUnpinnedCount: count) {
        case .accepted(let value):
            storeMaxUnpinnedClips(value)
            return value
        case .belowCurrentCount(let currentCount):
            // 사용자 의도는 *한도를 낮추는 것* 이므로 거부만 하고 끝내지 않는다 — 내릴 수 있는 데까지 내려준다.
            settingsToast.enqueue(.warn, L10n("toast.historyLimit.belowCurrent"))
            storeMaxUnpinnedClips(currentCount)
            return currentCount
        case .invalid:
            // 토스트 X — 오타 한 번에 경고를 띄우면 입력 도중 성가시다. 조용히 직전 값으로 되돌린다.
            return maxUnpinnedClips
        }
    }

    /// 증감 버튼 1회. 확정 입력과 같은 이유로 여기서도 개수를 그때그때 조회한다.
    ///
    /// 시작값을 인자로 받는 이유 — 입력란에 아직 확정하지 않은 숫자가 떠 있을 수 있고, 그 상태에서 버튼을
    /// 누르면 사용자는 *화면에 보이는 값* 기준으로 오르내리길 기대한다.
    /// 경계에서 막힐 때 토스트를 띄우지 않는 것은 의도다 — 연타하면 같은 경고가 그대로 쌓인다.
    /// - Returns: 입력란에 표시할 값.
    @discardableResult
    func stepMaxUnpinnedClips(from base: Int, delta: Int) async -> Int {
        let count = await currentUnpinnedCount()
        let next = HistoryLimitPolicy.step(from: base, delta: delta, currentUnpinnedCount: count)
        if next != maxUnpinnedClips { storeMaxUnpinnedClips(next) }
        return next
    }

    private func storeMaxUnpinnedClips(_ value: Int) {
        maxUnpinnedClips = value
        UserDefaults.standard.set(value, forKey: Constants.UserDefaultsKeys.maxUnpinnedClips)
        Logger.ui.info("maxUnpinnedClips set: \(value, privacy: .public)")
    }

    /// 핀 제외 보관 개수. 리포지토리가 없는 경로(단위 테스트)는 0 — 한도 하한이 1 이 되어 판정이 막히지 않는다.
    private func currentUnpinnedCount() async -> Int {
        guard let repository else { return 0 }
        do {
            return try await repository.unpinnedCount()
        } catch {
            // 조회 실패 시 0 을 쓰면 한도를 현재 개수 아래로 내릴 수 있게 되어 클립이 지워질 수 있다.
            // 안전한 쪽은 *지금 한도* 를 하한으로 삼는 것 — 내리는 것만 막히고 올리는 것은 그대로 된다.
            Logger.ui.error("보관 개수 조회 실패 — 현재 한도를 하한으로 사용: \(error)")
            return maxUnpinnedClips
        }
    }

    // MARK: - Shortcut validation (TASK-033 fix-2)

    /// 단축키 7항목 통합 핸들러. modifier 검증 + 충돌 검사 + nil (X 또는 modifier 누락) 처리.
    func handlePopoverShortcutChange(id: PopoverShortcutID, newShortcut: PopoverShortcut?, allIds: [PopoverShortcutID]) {
        guard !isRevertingShortcut else { return }

        guard let newShortcut else {
            resetPopoverShortcut(id: id)
            return
        }

        // modifier 검증 — Recorder 에서 modifier 없는 입력 시 rawValue 0 placeholder 박혀서 호출됨.
        if newShortcut.modifiersRawValue == 0 {
            revertPopoverShortcut(id: id)
            settingsToast.enqueue(.warn, L10n("toast.shortcut.modifierRequired"))
            return
        }

        // 충돌 검사 — 나머지 전 항목과 비교 (TASK-098 이후 기본 7종 + Pin 10종 = 17종).
        for otherId in allIds where otherId != id {
            guard let other = PopoverShortcutStore.get(otherId) else { continue }
            if other == newShortcut {
                revertPopoverShortcut(id: id)
                // TASK-098 — Pin 10종은 라벨이 모두 같아 순번까지 알려야 어느 번호와 겹쳤는지 안다.
                let otherLabel = otherId.conflictLabel
                let format = L10n("toast.shortcut.conflict")
                settingsToast.enqueue(.warn, String(format: format, otherLabel))
                return
            }
        }

        PopoverShortcutStore.set(newShortcut, for: id)
        lastValidPopoverShortcuts[id] = newShortcut
    }

    func resetPopoverShortcut(id: PopoverShortcutID) {
        guard let def = PopoverShortcutStore.defaults[id] else { return }
        isRevertingShortcut = true
        PopoverShortcutStore.set(def, for: id)
        lastValidPopoverShortcuts[id] = def
        isRevertingShortcut = false
    }

    private func revertPopoverShortcut(id: PopoverShortcutID) {
        isRevertingShortcut = true
        let target = lastValidPopoverShortcuts[id] ?? PopoverShortcutStore.defaults[id]!
        PopoverShortcutStore.set(target, for: id)
        lastValidPopoverShortcuts[id] = target
        isRevertingShortcut = false
    }

    /// *전체 되돌리기* 버튼 액션. 7항목 모두 default 로 복원.
    func resetAllShortcuts() {
        isRevertingShortcut = true
        for id in PopoverShortcutID.allCases {
            if let def = PopoverShortcutStore.defaults[id] {
                PopoverShortcutStore.set(def, for: id)
                lastValidPopoverShortcuts[id] = def
            }
        }
        isRevertingShortcut = false
        Logger.ui.info("All shortcuts reset to defaults")
    }

    // MARK: - Blocked apps
    func addBlockedApp(bundleId: String) {
        guard !bundleId.isEmpty, !blockedAppBundleIds.contains(bundleId) else { return }
        blockedAppBundleIds.append(bundleId)
        saveBlockedApps()
    }

    func removeBlockedApp(bundleId: String) {
        blockedAppBundleIds.removeAll { $0 == bundleId }
        saveBlockedApps()
    }

    func selectAppFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                    self?.addBlockedApp(bundleId: id)
                }
            }
        }
    }

    private func loadBlockedApps() {
        blockedAppBundleIds = UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKeys.blockedAppBundleIds) ?? []
    }

    private func saveBlockedApps() {
        UserDefaults.standard.set(blockedAppBundleIds, forKey: Constants.UserDefaultsKeys.blockedAppBundleIds)
    }

    // MARK: - Data folder
    func openDataFolder() {
        NSWorkspace.shared.open(AppDataPath.dataFolder())
    }

    // MARK: - GitHub / Releases
    func openGitHubRepo() {
        if let url = URL(string: "https://github.com/angar2/stash") {
            NSWorkspace.shared.open(url)
        }
    }

    /// TASK-033 — 정보 탭 *릴리즈 노트* 버튼 액션. GitHub releases 페이지 열기.
    func openReleaseNotes() {
        if let url = URL(string: "https://github.com/angar2/stash/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 자동 업데이트 (TASK-102)

    /// Composition Root 가 주입. `nil` 이면 설정 화면의 업데이트 항목이 표시되지 않는다 (테스트 경로).
    func setUpdateService(_ service: UpdateService) {
        self.updateService = service
    }

    /// 정보 탭 *업데이트 확인*. 진행·결과는 `updateCheckState` 로 노출되어 항목 우측 문구가 된다.
    func checkForUpdates() {
        updateService?.checkForUpdatesManually()
    }

    /// 일반 탭 *업데이트 자동 확인* 토글. 저장 버튼 없이 즉시 반영한다.
    func setAutomaticUpdateChecks(_ enabled: Bool) {
        updateService?.setAutomaticChecksEnabled(enabled)
    }

    /// 자동 확인 켜짐 여부. 저장은 Sparkle 이 담당하므로 여기서는 그 값을 그대로 읽는다.
    var automaticUpdateChecksEnabled: Bool {
        updateService?.automaticChecksEnabled ?? false
    }

    /// 정보 탭 항목 우측에 표시할 확인 상태. `nil` = 표시할 것 없음.
    var updateCheckState: ManualUpdateCheckState? {
        updateService?.manualCheckState
    }

    /// 업데이트 항목 표시 여부 — 창구가 주입되지 않은 경로(테스트·프리뷰)에서는 그리지 않는다.
    var updateAvailable: Bool { updateService != nil }
}
