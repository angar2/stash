// @main 진입점 + Composition Root — 전체 의존성 와이어링 (ARCHITECTURE §7-2 / §9-4)
import SwiftUI
import AppKit
import Combine
import OSLog
import KeyboardShortcuts

@main
struct StashApp: App {
    // MARK: - Persistence
    let repository: any ClipRepository

    // MARK: - System protocol implementations
    let pasteboard: any Pasteboard
    let fileClipService: any FileClipService

    // MARK: - Services
    let permissionService: PermissionService
    let notificationService: NotificationService
    let loginItemService: LoginItemService
    let clipboardWatcher: ClipboardWatcher
    /// TASK-033 — *저장하지 않을 앱* 백엔드 — frontmost 앱 번들 ID 추적. ClipboardWatcher.buildClip 분기에서 사용.
    let frontmostAppTracker: FrontmostAppTracker
    let hotkeyManager: HotkeyManager
    let hotkeyMonitor: HotkeyMonitor
    let pasteService: PasteService
    /// TASK-102 — 자동 업데이트 창구. 업데이터 보유 + 즉시 확인 / 자동 확인 토글 / 배너 대기 상태.
    let updateService: UpdateService

    // MARK: - UI ViewModels
    let clipsViewModel: ClipsViewModel
    let settingsViewModel: SettingsViewModel
    let onboardingViewModel: OnboardingViewModel

    // MARK: - UI controllers (NSStatusItem retain — App lifetime)
    let statusItemController: StatusItemController
    /// 1·2·3 호출 방식 통합 popover Window (TASK-018) — Method1/2/3Window 폐기 후 단일 인스턴스.
    let popoverWindow: PopoverWindow
    /// TASK-029 — SwiftUI Settings Scene 폐기 + 환경설정 윈도우 단일 controller. 마우스 클릭 / ⌘+, / ESC 모든 진입점 단일화.
    let preferencesController: PreferencesWindowController
    let toastQueue: ToastQueue
    let toastWindowController: ToastWindowController
    let permissionToastNotifier: PermissionToastNotifier
    /// 권한 변경 시 hotkeyMonitor 자동 start/stop — App lifetime 보관 (구독 유지).
    let permissionMonitorBridge: AnyCancellable
    /// NSWorkspace 앱 활성화 감지 시 권한 recheck — 사용자가 시스템 설정에서 권한 부여 후 다른 앱으로 돌아올 때 자동 감지 (TASK-017 fix-3).
    let permissionRefresherObserver: NSObjectProtocol

    init() {
        // TASK-089 Phase 1 — XCUITest launch argument 사전 처리. 일반 사용자 launch (`--ui-test` 미주입) 시 no-op.
        // 본 호출은 UserDefaults register / AppLanguageService.applyOnLaunch 이전 실행 — onboarding flag reset / language override 가 후속 흐름에 즉시 반영.
        LaunchArguments.applyEarlyEnvironment()
        let launchArgs = LaunchArguments.parse()

        // TASK-033 — UserDefaults default values 등록. 사용자 설정 없을 때 기본값. autoPasteEnabled default true (자동 paste 기본 ON).
        // TASK-037 — 디스플레이 탭 신규 — clipsPerPage default 6 (TASK-036 토큰 추정값 인계), autoFitClipListHeight default false.
        // TASK-052 — 디스플레이 탭 *단축키 설명 표시* 토글 default true (신규 사용자 학습 보조 — 사용자가 숙지 후 명시적 OFF).
        UserDefaults.standard.register(defaults: [
            Constants.UserDefaultsKeys.autoPasteEnabled: true,
            Constants.UserDefaultsKeys.clipsPerPage: Constants.clipsPerPageDefault,
            Constants.UserDefaultsKeys.autoFitClipListHeight: false,
            Constants.UserDefaultsKeys.hintBarVisible: true
        ])

        // TASK-073 — 앱 사용자 표시 언어 적용. UserDefaults `appLanguage` 키 부재 시 systemDefault (한국어 OS → .korean / 그 외 → .english) 박음 + AppleLanguages override.
        // 본 호출은 SwiftUI / AppKit 모든 view 생성 *전* 실행되어야 첫 lookup 부터 정확한 언어 적용.
        AppLanguageService.applyOnLaunch()

        // ① Persistence — 가장 안쪽부터 (ARCHITECTURE §9-4 step 2-3)
        let dataFolder = AppDataPath.dataFolder()
        let dbPath = AppDataPath.databaseFile()
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        let grdbRepo: GRDBClipRepository
        var dbCorruptionRecovered = false
        do {
            grdbRepo = try GRDBClipRepository(dbPath: dbPath)
        } catch {
            Logger.database.error("DB init failed, removing and recreating: \(error)")
            try? FileManager.default.removeItem(at: dbPath)
            // 손상 파일 제거 후 재생성 — 실패하면 앱 시작 불가 (fatalError 허용)
            grdbRepo = try! GRDBClipRepository(dbPath: dbPath)
            dbCorruptionRecovered = true
        }
        self.repository = grdbRepo

        // TASK-100 — 보관 한도 첫 실행 초기화. **클립보드 감시 생성보다 앞** 이어야 한다:
        // 한도가 정해지기 전에 클립 하나가 저장되면 그 insert 가 기본값(50) 기준으로 LRU 정리를 돌려
        // 한도 200 시절에 쌓아둔 클립을 지운다. 그래서 비동기가 아니라 동기 조회를 쓴다.
        // 조회 실패는 DB 를 새로 만든 직후(손상 복구 포함)와 구분되지 않으므로 0 으로 본다 — 그 경우 기본값이 맞다.
        do {
            let unpinned = try grdbRepo.unpinnedCountSync()
            HistoryLimitPolicy.initializeStoredLimitIfNeeded(currentUnpinnedCount: unpinned)
        } catch {
            Logger.database.error("보관 한도 초기화용 개수 조회 실패 — 0 으로 진행: \(error)")
            HistoryLimitPolicy.initializeStoredLimitIfNeeded(currentUnpinnedCount: 0)
        }
        Logger.appLifecycle.info("보관 한도 = \(Constants.maxUnpinnedClips, privacy: .public)")

        // ② 시스템 wrapper (protocol 구현체 생성 — ARCHITECTURE §9-4 step 4)
        let pb: any Pasteboard = SystemPasteboard.shared
        let fcs: any FileClipService = DirectFileClipService()
        self.pasteboard = pb
        self.fileClipService = fcs

        // ③ 시스템 wrapper Service (ARCHITECTURE §9-4 step 5)
        let permSvc = PermissionService(checker: AXPermissionChecker())
        self.permissionService = permSvc
        self.notificationService = NotificationService(center: UNNotificationCenterImpl())
        self.loginItemService = LoginItemService(registrar: SMLoginItemRegistrar())

        // ④ ToastQueue + ToastWindow (모든 ViewModel에서 발행) — TASK-026: ClipboardWatcher onUserMessage 콜백 주입 위해 Watcher 생성 전으로 이동.
        let toastQ = ToastQueue()
        self.toastQueue = toastQ
        self.toastWindowController = ToastWindowController(queue: toastQ)

        // ⑤ 도메인 Service — 생성자 주입 (ARCHITECTURE §9-4 step 5)
        // TASK-033 — FrontmostAppTracker 신규. ClipboardWatcher 에 주입해 *저장하지 않을 앱* 매칭 시 클립 저장 skip.
        let frontmostTracker = FrontmostAppTracker()
        self.frontmostAppTracker = frontmostTracker
        // TASK-043 — UserDefaults 마지막 상태 복원. 미등록 시 true default.
        let captureEnabledInit: Bool = {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Constants.UserDefaultsKeys.clipboardCaptureEnabled) == nil { return true }
            return defaults.bool(forKey: Constants.UserDefaultsKeys.clipboardCaptureEnabled)
        }()
        let watcher = ClipboardWatcher(
            pasteboard: pb,
            fileClipService: fcs,
            repository: grdbRepo,
            // TASK-026 — 임계 초과 / 부분 실패 시 인앱 토스트 dispatch.
            // TASK-066 — 시그니처 (String) → (ToastKind, String) 확장 (warn 한도 초과 / error 저장 실패 분기).
            onUserMessage: { kind, msg in
                await MainActor.run {
                    toastQ.enqueue(kind, msg)
                }
            },
            frontmostTracker: frontmostTracker,
            enabled: captureEnabledInit
        )
        self.clipboardWatcher = watcher
        self.hotkeyManager = HotkeyManager(
            registrar: KeyboardShortcutsRegistrar.shared,
            permissionService: permSvc
        )
        self.hotkeyMonitor = HotkeyMonitor(permissionService: permSvc)
        let pasteSvc = PasteService(
            synthesizer: CGEventPasteSynthesizer(),
            pasteboard: pb,
            repository: grdbRepo,
            permissionService: permSvc,
            // TASK-023 회귀 (e) fix — paste 직후 watcher 에 own-write 통보해 다음 tick 에서 자기 자신 박은 변경 idle.
            onPasteboardWritten: { [watcher] in
                await watcher.acknowledgeOwnWrite()
            },
            // TASK-026 fix — paste 진행 동안 watcher tick 자체 차단. 다중 파일 saveFiles race 차단.
            setPastePending: { [watcher] pending in
                await watcher.setPastePending(pending)
            }
        )
        self.pasteService = pasteSvc

        // ⑤-2 자동 업데이트 (TASK-102) — 생성 즉시 업데이터가 기동해 다음 runloop 부터 자동 확인 주기가 돈다.
        // App lifetime 보관. UI(설정 항목 / popover 배너)는 이 창구만 사용한다.
        let updateSvc = UpdateService()
        self.updateService = updateSvc

        // ⑥ UI ViewModel (View lifetime 결속 — Composition Root에서 보관, View는 @Bindable로 접근)
        let clipsVM = ClipsViewModel(repository: grdbRepo, pasteService: pasteSvc, fileClipService: fcs, toastQueue: toastQ)
        // TASK-043 — toggleCapture 호출 시 watcher.setEnabled actor 메서드 호출 대상 주입.
        clipsVM.setClipboardWatcher(watcher)
        self.clipsViewModel = clipsVM
        // TASK-100 — 보관 한도 판정에 쓸 *핀 제외 개수* 조회 경로로 리포지토리 주입.
        let settingsVM = SettingsViewModel(loginItemService: self.loginItemService, repository: grdbRepo)
        // TASK-102 — 설정 두 탭(업데이트 확인 / 자동 확인 토글)이 쓸 창구 주입.
        settingsVM.setUpdateService(updateSvc)
        self.settingsViewModel = settingsVM
        let onboardingVM = OnboardingViewModel(permissionService: permSvc)
        self.onboardingViewModel = onboardingVM

        // ⑦ Permission 토스트 + 시스템 알림 발행자
        self.permissionToastNotifier = PermissionToastNotifier(
            publisher: permSvc.statusPublisher,
            toastQueue: toastQ,
            notificationService: self.notificationService
        )

        // ⑧ UI controllers (NSStatusItem retain) — HistoryPopover 호스팅
        // 1·2·3 호출 방식 통합 popover Window (TASK-018). StatusItemController 와 HotkeyMonitor 모두 동일 인스턴스 공유.
        // TASK-029 — preferencesController 를 App lifetime 으로 보관 + popover onOpenSettings 콜백이 controller.show() 호출 (단일 진입점).
        // TASK-098 — 단축키 탭 `PIN 단축키` 묶음이 핀 항목의 명칭·값을 표시·수정하므로 클립 뷰모델도 주입.
        let prefsController = PreferencesWindowController(viewModel: settingsVM, clipsViewModel: clipsVM)
        self.preferencesController = prefsController
        let popover = PopoverWindow(
            viewModel: clipsVM,
            settingsViewModel: settingsVM,  // TASK-054 fix-1 — windowWillResize 안에서 setClipsPerPage 직접 호출.
            updateService: updateSvc,       // TASK-102 — 헤더 업데이트 배너 + 높이 cap.
            onOpenSettings: { [prefsController] in prefsController.show() }
        )
        self.popoverWindow = popover
        self.statusItemController = StatusItemController(popoverWindow: popover)

        // ⑨ HotkeyMonitor callback 연결 — TASK-018 Phase 9 ⌘ hold *v1.0 보류* (onHoldStart/onHoldEnd 미연결). TASK-046 — ⌘ double-tap 트리거 폐기로 `onDoubleTap` 콜백 삭제. 방식 2 popover 호출 자체는 유지 — 트리거는 ⑨-2 SPM 단축키 (default `⌘⇧C` — TASK-065 / TASK-090) 가 담당.
        // ⌘ hold 보류 사유: (a) 일반 ⌘+key 단축키 사용 중 의도 안 한 popover 오트리거 사용성 저해, (b) 방식 1/2 popover 열린 상태에서 단축키 입력 시 방식 3 진입으로 전환되어 사용성 저해. 코드 분기(`PopoverWindow.mode == .method3`)는 유지 (미래 부활 가능). 호출 사이트 X.
        let hotkeyMon = self.hotkeyMonitor
        hotkeyMon.onHoldStart = nil
        hotkeyMon.onHoldEnd = nil

        // ⑨-2 TASK-032 — KeyboardShortcuts SPM (Carbon RegisterEventHotKey 기반, Accessibility 권한 무관) 진입점 등록.
        // default `⌘⇧C` (TASK-065 정정 / TASK-090 — TASK-032 잔존 fallback (`⌘⇧V` 강제 setShortcut) 제거. `.popoverOpen` default 적용은 ⑨-2-2 `PopoverShortcutStore.registerDefaultsIfNeeded()` 단일 진실 진입점 위임 — `PopoverShortcutStore.defaults[.popoverOpen]` = `⌘⇧C`).
        // HotkeyMonitor (⌘ hold 영역, modifier-only 후킹, 권한 필수, TASK-018 Phase 9 보류) 와 별개 진입점 — 권한 거부 사용자도 popover 진입 가능. TASK-046 — 방식 2 popover 호출 트리거 단일화 (⌘ double-tap 트리거 폐기 후 SPM 단축키 통로만 / TASK-032 시점 ⌘⇧V SPM 을 *방식 4* 별도 진입점으로 잘못 분리 박은 명명도 본 task로 통합 정합 — 방식 4 폐기 + 방식 2 트리거 흡수).
        self.hotkeyManager.register(name: .popoverOpen) { [popover, clipsVM] in
            Task { @MainActor in
                Logger.hotkey.info("popoverOpen shortcut triggered (방식 2 — SPM)")
                await clipsVM.reload()
                popover.show(mode: .method2)
            }
        }

        // ⑨-2-1 TASK-098 — Pin 직접 paste 전역 단축키 10종 등록 (기본 `⌥⌘1`~`⌥⌘9`, `⌥⌘0`).
        // `.popoverOpen` 과 같은 SPM Carbon 경로 — *어디서나 동작*이 기능 본질이라 popover localMonitor 로는 성립하지 않는다.
        // 대상은 *자리 번호* (`pin_slot` 1~10) 기준이다 — TASK-098 검수 정정.
        // 이전에는 `pinnedClips` 배열 위치를 순번으로 썼는데, 그러면 앞자리를 핀 해제한 순간 뒤 항목이 당겨져
        // **같은 조합이 다른 클립을 붙여넣었다**. 자리는 해제해도 당겨지지 않으므로 조합이 가리키는 대상이 고정된다.
        // 그 자리가 비어 있으면 오류 표시 없이 무시한다 (전역 단축키라 오타성 입력이 잦음 — FEATURES F-004).
        for id in PopoverShortcutID.pinPasteIDs {
            guard let name = id.globalName, let ordinal = id.pinOrdinal else { continue }
            self.hotkeyManager.register(name: name) { [popover, clipsVM] in
                Task { @MainActor in
                    await clipsVM.reload()
                    let slots = clipsVM.pinnedClips.map(\.pinSlot)
                    let pinnedCount = slots.count
                    guard let targetIdx = PinPasteShortcutResolver.resolvePinTargetIndex(
                        ordinal: ordinal,
                        slots: slots
                    ) else {
                        Logger.hotkey.info("pinPaste 무시 — ordinal=\(ordinal, privacy: .public) pinnedCount=\(pinnedCount, privacy: .public) (그 자리 비어 있음)")
                        return
                    }
                    Logger.hotkey.info("pinPaste 실행 — ordinal=\(ordinal, privacy: .public) pinnedCount=\(pinnedCount, privacy: .public) idx=\(targetIdx, privacy: .public)")
                    // popover 안 paste 와 동일 경로 — 권한 × 자동 붙여넣기 매트릭스(F-003)를 그대로 상속.
                    // popover 가 떠 있으면 기존 흐름대로 닫고 붙이고, 닫혀 있으면 hide 가 no-op 이라 현재 앱에 그대로 붙는다.
                    await PopoverPanel.performPasteFlow(
                        viewModel: clipsVM,
                        idx: targetIdx,
                        zone: .pin,
                        sourceLabel: "PinPasteHotkey(\(ordinal))",
                        hide: { if popover.isVisible { popover.hide() } }
                    )
                }
            }
        }

        // ⑨-2-2 TASK-033 fix-2 — popover 안 변경 가능 단축키 6종 default 등록 → 자체 `PopoverShortcutStore` 사용.
        // 사유: SPM `setShortcut` 이 Carbon RegisterEventHotKey 글로벌 hotkey 등록을 자동 트리거 → ⌘V/⌘C 같은 시스템 표준 단축키 매핑 시 시스템 paste/copy 자체 무력화 + popover localMonitor 도달 X. → SPM 사용 X, 자체 UserDefaults JSON storage 활용.
        PopoverShortcutStore.registerDefaultsIfNeeded()

        // ⑨-3 권한 변경 시 hotkeyMonitor 자동 재시작 + ViewModel state 동기 (TASK-017 Phase 2-A / TASK-024) —
        // 권한 부여 *전* 상태였으면 init 1회 start()가 skip됨. 이후 사용자가 권한 부여해도 재시작 트리거 없음 → 영원히 미동작.
        // statusPublisher 구독해서 .granted 변경 시 start, .denied/.unknown 변경 시 stop. start()는 stop() 선행 호출로 멱등.
        // TASK-024 — 동일 sink 안에서 ClipsViewModel + SettingsViewModel 의 `accessibilityGranted` 동시 갱신. (1) ClipsViewModel 의 ⌘V 권한 게이트 동적 토글 + 힌트바 회색조 분기. (2) SettingsViewModel 의 *autoPaste 라디오 활성 분기* 의 호출처 누락 fix — 기존 `updateAccessibilityGranted` 정의만 되어 있고 호출처 0건이라 권한 O 사용자도 autoPaste 선택 불가했던 결함 정합.
        self.permissionMonitorBridge = permSvc.statusPublisher
            .receive(on: RunLoop.main)
            .sink { [hotkeyMon, clipsVM, settingsVM] status in
                Task { @MainActor in
                    let granted: Bool
                    switch status {
                    case .granted:
                        Logger.hotkey.info("Permission status changed → granted — hotkeyMonitor 자동 start + ViewModel state 갱신")
                        await hotkeyMon.start()
                        granted = true
                    case .denied, .unknown:
                        Logger.hotkey.info("Permission status changed → \(String(describing: status), privacy: .public) — hotkeyMonitor 자동 stop + ViewModel state 갱신")
                        hotkeyMon.stop()
                        granted = false
                    }
                    clipsVM.updateAccessibilityGranted(granted)
                    settingsVM.updateAccessibilityGranted(granted)
                }
            }

        // ⑨-4 권한 변경 감지 트리거 (TASK-017 fix-3) — stash는 LSUIElement=true (메뉴바 상주)라 background.
        // 사용자가 시스템 설정에서 Accessibility 권한 부여 후 시스템 설정을 닫고 다른 앱으로 돌아올 때 NSWorkspace.didActivateApplicationNotification 발화.
        // 그 시점에 permSvc.recheck() 호출 → status .denied → .granted 변경 감지 → publisher emit → bridge → hotkeyMon.start() 자동.
        self.permissionRefresherObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [permSvc] _ in
            Task { await permSvc.recheck() }
        }

        // ⑧ Startup — async 작업은 Task로 위임 (ARCHITECTURE §9-4 step 8-9)
        // TASK-089 Phase 4 fix — UI 테스트 모드에서 watcher.start() skip. 시스템 클립보드 외부 변경이 시드 외 추가 row 캡쳐하는 flaky 차단.
        Task {
            if !launchArgs.isUITest {
                await watcher.start()
                Logger.appLifecycle.info("ClipboardWatcher started")
            } else {
                Logger.appLifecycle.info("ClipboardWatcher start skipped — UI test mode")
            }
        }
        Task { @MainActor in
            await permSvc.recheck()
            Logger.appLifecycle.info("Initial permission check done")
            await hotkeyMon.start()
        }

        // ⑩ DB 손상 복구 시 시스템 알림
        if dbCorruptionRecovered {
            let notifSvc = self.notificationService
            Task {
                await notifSvc.notify(.dbCorruptionRecovered)
                Logger.database.warning("DB 손상 복구 — 시스템 알림 발송")
            }
        }

        // ⑩-2 TASK-034 — 앱 시작 시 orphan sweep. DB referencedPaths set ↔ clips/ 폴더 diff → 미참조 파일 삭제.
        // 디스크 삭제 실패 (권한 / 파일 잠김) fallback + 기존 누적 고아 자동 회수. DB 손상 복구 직후 (빈 DB) 도 동일 흐름으로 카피본 전체 정리.
        // 백그라운드 Task — popover 첫 진입 지연 0 보장.
        Task { [grdbRepo, fcs] in
            let clips = (try? await grdbRepo.fetchAll()) ?? []
            var referenced: Set<String> = []
            for clip in clips {
                if clip.isMultiFile, let entries = clip.fileEntries {
                    for entry in entries where !entry.isFileExternal {
                        referenced.insert(entry.filePath)
                    }
                } else if !clip.isFileExternal, let path = clip.filePath {
                    referenced.insert(path)
                }
            }
            await fcs.sweepOrphans(referencedPaths: referenced)
            Logger.database.info("Startup orphan sweep done — referenced=\(referenced.count)")
        }

        // TASK-070 — 첫 실행 시 자동 표시 (원래 정책). 윈도우 정책 (X 버튼 제거 + ESC 차단 + 완료 버튼 only) 으로 1회 보장.
        // TASK-089 Phase 4 — UI 테스트에서 popover/settings 즉시 표시 박힐 때는 onboarding 자동 표시 skip (윈도우 간섭 회피).
        let suppressOnboardingForUITest = launchArgs.isUITest && (launchArgs.showPopover || launchArgs.showSettings)
        if !onboardingVM.hasCompleted && !suppressOnboardingForUITest {
            Task { @MainActor in
                Self.presentOnboarding(viewModel: onboardingVM)
            }
        }

        // TASK-089 Phase 1 — UI 테스트 모드: 시드 클립 박음 + popover/settings 즉시 표시 분기.
        if launchArgs.isUITest {
            if launchArgs.seedClipsCount > 0 {
                let count = launchArgs.seedClipsCount
                Task { [grdbRepo, clipsVM] in
                    await Self.seedClipsForUITest(count: count, repository: grdbRepo)
                    await clipsVM.reload()
                    Logger.appLifecycle.info("UI test: seeded \(count) clips")
                }
            }
            if launchArgs.showPopover {
                Task { @MainActor [popover, clipsVM] in
                    // popover 즉시 표시 — 시드 반영 대기 후. 짧은 지연 (300ms) 으로 init 부수 작업 + seed insert 완료 보장.
                    try? await Task.sleep(for: .milliseconds(300))
                    await clipsVM.reload()
                    popover.show(mode: .method2)
                    // TASK-089 Phase 4 — UI 테스트 한정 NSApp.activate. popover panel `nonactivatingPanel` 이라 XCUI hit testing 도달 X — 일반 사용자 흐름 (TASK-020 정합) 영향 0.
                    NSApp.activate(ignoringOtherApps: true)
                    Logger.appLifecycle.info("UI test: popover shown (method2) + activated")
                }
            }
            if launchArgs.showSettings {
                Task { @MainActor [prefsController] in
                    try? await Task.sleep(for: .milliseconds(200))
                    prefsController.show()
                    prefsController.recenterOnPrimaryScreenForUITest()
                    Logger.appLifecycle.info("UI test: settings window shown + recentered")
                }
            }
        }

        Logger.appLifecycle.info("StashApp init complete — all services wired")
    }

    /// XCUITest 시드 클립 박음 헬퍼 — text 타입 단순 시퀀스. Phase 4 popover 시나리오용 데이터 베이스.
    private static func seedClipsForUITest(count: Int, repository: any ClipRepository) async {
        let baseDate = Date()
        for i in 0..<count {
            let clip = Clip(
                id: UUID(),
                type: .text,
                body: "UITest seed clip #\(i + 1)",
                filePath: nil,
                isFileExternal: false,
                fileOriginalPath: nil,
                fileBookmark: nil,
                sourceAppBundleId: "com.angar2.stash.uitest",
                isPinned: false,
                createdAt: baseDate.addingTimeInterval(TimeInterval(-i)),
                lastUsedAt: baseDate.addingTimeInterval(TimeInterval(-i))
            )
            _ = try? await repository.insert(clip)
        }
    }

    /// TASK-070 — onboarding 윈도우 표시. 시스템 표준 NSWindow (titled + fullSizeContentView + transparent titlebar) — 시스템 자체가 둥근 corner + 보더 + 그림자 박음. 종료 = 완료 버튼 only (closable 버튼 3종 hidden + ESC 차단 = OnboardingNSWindow.cancelOperation no-op).
    @MainActor
    static func presentOnboarding(viewModel: OnboardingViewModel) {
        let contentRect = NSRect(
            x: 0, y: 0,
            width: DesignTokens.WindowSize.onboardingWidth,
            height: 380
        )
        let window = makeOnboardingWindow(contentRect: contentRect)
        attachOnboardingContent(window: window, contentRect: contentRect, viewModel: viewModel)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Logger.appLifecycle.info("Onboarding window presented")
    }

    @MainActor
    private static func makeOnboardingWindow(contentRect: NSRect) -> OnboardingNSWindow {
        let window = OnboardingNSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = ""
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        return window
    }

    @MainActor
    private static func attachOnboardingContent(window: OnboardingNSWindow, contentRect: NSRect, viewModel: OnboardingViewModel) {
        // NSVisualEffectView — Liquid Glass. 시스템 NSWindow 가 외곽 corner/보더/그림자 자동 박음 — VE 자체 cornerRadius/border 박지 X.
        let ve = NSVisualEffectView(frame: contentRect)
        ve.material = .popover
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.isEmphasized = true
        ve.autoresizingMask = [.width, .height]
        window.contentView = ve

        let hosting = NSHostingView(
            rootView: OnboardingWindow(
                viewModel: viewModel,
                onClose: { [weak window] in
                    window?.orderOut(nil)
                }
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = ve.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        ve.addSubview(hosting)
    }

    var body: some Scene {
        // NOTE: MenuBarExtra 미사용 — 좌/우 클릭 분기 한계로 NSStatusItem 직접 사용 (ARCHITECTURE §9-2)
        // TASK-029 — SwiftUI Settings Scene 본문 비움. 자동 ⌘+, 메뉴 항목은 `.commands` `CommandGroup(replacing: .appSettings)` 가 PreferencesWindowController.show() 호출로 재등록 (마우스 클릭 / ⌘+, / ESC 단일 controller 경유).
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n("preferences.row") + "...") {
                    preferencesController.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    // 전체 삭제 NSAlert 모달 제거 (디자인 popover.jsx 정합 — 즉시 실행 + 토스트). 검색바 안 "전체 삭제" 텍스트 버튼 또는 단축키 ⌥⌘⌫·⌘⇧⌫ 호출 시 ClipsViewModel.deleteAllExceptPinned() 즉시 실행.
}
