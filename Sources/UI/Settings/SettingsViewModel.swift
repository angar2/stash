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

    // MARK: - Display tab (TASK-037)
    /// 한 페이지에 보여줄 클립 개수. 1~30 clamp. default 6.
    /// 변경 시 UserDefaults 동기화 + ClipsViewModel.effectivePageSize() 가 매 호출 시점 최신값 조회 + popover 가 @AppStorage 또는 Observation 으로 즉시 재렌더.
    var clipsPerPage: Int = Constants.clipsPerPageDefault
    /// 클립 리스트 컨테이너 높이 자동 조정 체크박스. ON 시 컨테이너 행 수 = `max(min(visibleCount, N), min(N, 3))`. default false.
    var autoFitClipListHeight: Bool = false
    /// TASK-052 — popover 하단 `KeyboardHintsView` 표시 여부. default true. OFF 시 힌트바 (상단 Divider 포함) 전체 비표시 + popover height 자동 축소.
    var hintBarVisible: Bool = true

    /// TASK-033 — 환경설정 윈도우 내부 토스트 큐 (popover 토스트와 별개 시스템). Login Item 실패 / 권한 변동 / 단축키 modifier 검증 / 충돌 검사 토스트 발행 채널.
    let settingsToast: ToastQueue = ToastQueue()

    private let loginItemService: LoginItemService
    /// TASK-033 fix-2 — 7항목 (popoverOpen + 6종) 변경 revert 용 마지막 valid 단축키 추적.
    private var lastValidPopoverShortcuts: [PopoverShortcutID: PopoverShortcut] = [:]
    /// TASK-033 — revert 호출 재진입 가드.
    private var isRevertingShortcut: Bool = false

    init(loginItemService: LoginItemService) {
        self.loginItemService = loginItemService
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
            if !autoPasteEnabled {
                autoPasteEnabled = true
                UserDefaults.standard.set(true, forKey: "autoPasteEnabled")
                Logger.ui.info("Permission granted — autoPasteEnabled auto-ON")
            }
            settingsToast.enqueue(.success, String(localized: "toast.permission.granted"), ttl: 2.5)
        } else if prev && !granted {
            if autoPasteEnabled {
                autoPasteEnabled = false
                UserDefaults.standard.set(false, forKey: "autoPasteEnabled")
                Logger.ui.info("Permission revoked — autoPasteEnabled forced OFF")
            }
            settingsToast.enqueue(.warn, String(localized: "toast.permission.revoked"), ttl: 2.5)
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
            settingsToast.enqueue(.error, String(localized: "toast.loginItem.failed"), ttl: 3.0)
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
        UserDefaults.standard.set(enabled, forKey: "autoPasteEnabled")
        Logger.ui.info("autoPasteEnabled set: \(enabled, privacy: .public)")
    }

    private func loadAutoPasteEnabled() {
        // TASK-033 — 마이그레이션. 기존 "pasteMode" 키 잔존값 (PasteMode.rawValue) → boolean 변환 + 기존 키 제거.
        if let raw = UserDefaults.standard.string(forKey: "pasteMode") {
            let migrated = (raw == "autoPaste")
            UserDefaults.standard.set(migrated, forKey: "autoPasteEnabled")
            UserDefaults.standard.removeObject(forKey: "pasteMode")
            autoPasteEnabled = migrated
            Logger.ui.info("Migrated pasteMode -> autoPasteEnabled: \(migrated, privacy: .public)")
            return
        }
        // default = true (자동 paste 기본 ON — 권한 부여 후 자연 활성)
        if UserDefaults.standard.object(forKey: "autoPasteEnabled") != nil {
            autoPasteEnabled = UserDefaults.standard.bool(forKey: "autoPasteEnabled")
        }
    }

    // MARK: - Display preferences (TASK-037)

    /// 한 페이지 클립 수 변경. 1~30 clamp + UserDefaults 갱신 + state 갱신 (Observation 트리거) + NSPanel frame 재계산 알림.
    func setClipsPerPage(_ value: Int) {
        let clamped = max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, value))
        clipsPerPage = clamped
        UserDefaults.standard.set(clamped, forKey: "clipsPerPage")
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
        Logger.ui.info("clipsPerPage set: \(clamped, privacy: .public)")
    }

    /// 높이 자동 조정 체크박스 토글. UserDefaults 갱신 + state 갱신 + NSPanel frame 재계산 알림.
    func setAutoFitClipListHeight(_ value: Bool) {
        autoFitClipListHeight = value
        UserDefaults.standard.set(value, forKey: "autoFitClipListHeight")
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
        Logger.ui.info("autoFitClipListHeight set: \(value, privacy: .public)")
    }

    /// TASK-052 — 단축키 설명 표시 체크박스 토글. UserDefaults 갱신 + state 갱신 + NSPanel frame 재계산 알림.
    /// `HistoryPopover` 가 `@AppStorage("hintBarVisible")` 로 동일 키 추적 → SwiftUI body 즉시 재계산 (KeyboardHintsView if 분기), `displayLayoutDidChange` notification 으로 `PopoverWindow._performRefreshFrame` 가 fittingSize 재측정 후 NSPanel.setFrame.
    func setHintBarVisible(_ value: Bool) {
        hintBarVisible = value
        UserDefaults.standard.set(value, forKey: "hintBarVisible")
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
        Logger.ui.info("hintBarVisible set: \(value, privacy: .public)")
    }

    private func loadDisplayPreferences() {
        // register defaults 가 StashApp 진입점에서 박혔으므로 integer/bool 조회 시 default 값 (6 / false / true) 자연 반환.
        // 단, 사용자가 잘못된 값 (음수 / 30 초과) 박은 케이스 방어 — clamp.
        let rawN = UserDefaults.standard.integer(forKey: "clipsPerPage")
        clipsPerPage = max(Constants.clipsPerPageMin, min(Constants.clipsPerPageMax, rawN))
        autoFitClipListHeight = UserDefaults.standard.bool(forKey: "autoFitClipListHeight")
        // TASK-052 fix — register defaults 의존 폐기 + `loadAutoPasteEnabled` 패턴 정합 (`object(forKey:) != nil` 분기). default true 는 stored property 초기값 으로 보존 — 사용자가 toggle 한 적 없으면 시각 ON 유지.
        if UserDefaults.standard.object(forKey: "hintBarVisible") != nil {
            hintBarVisible = UserDefaults.standard.bool(forKey: "hintBarVisible")
        }
        Logger.ui.info("loadDisplayPreferences — clipsPerPage=\(self.clipsPerPage, privacy: .public) autoFit=\(self.autoFitClipListHeight, privacy: .public) hintBarVisible=\(self.hintBarVisible, privacy: .public)")
    }

    /// TASK-033 — 일반 탭 *"시스템 접근 권한"* 링크 클릭 핸들러. macOS 시스템 설정 Accessibility 화면 직접 열기.
    func openSystemSettingsForAccessibility() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// TASK-033 — 일반 탭 히스토리 한도 정보 라인 동적 바인딩.
    var maxUnpinnedClips: Int { Constants.maxUnpinnedClips }

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
            settingsToast.enqueue(.warn, String(localized: "toast.shortcut.modifierRequired"), ttl: 3.0)
            return
        }

        // 충돌 검사 — 다른 6항목과 비교
        for otherId in allIds where otherId != id {
            guard let other = PopoverShortcutStore.get(otherId) else { continue }
            if other == newShortcut {
                revertPopoverShortcut(id: id)
                let otherLabel = String(localized: String.LocalizationValue(otherId.labelKey))
                let format = String(localized: "toast.shortcut.conflict")
                settingsToast.enqueue(.warn, String(format: format, otherLabel), ttl: 3.0)
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
        blockedAppBundleIds = UserDefaults.standard.stringArray(forKey: "blockedAppBundleIds") ?? []
    }

    private func saveBlockedApps() {
        UserDefaults.standard.set(blockedAppBundleIds, forKey: "blockedAppBundleIds")
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
}
