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
        // TASK-033 — UserDefaults default values 등록. 사용자 설정 없을 때 기본값. autoPasteEnabled default true (자동 paste 기본 ON).
        // TASK-037 — 디스플레이 탭 신규 — clipsPerPage default 6 (TASK-036 토큰 추정값 인계), autoFitClipListHeight default false.
        // TASK-052 — 디스플레이 탭 *단축키 설명 표시* 토글 default true (신규 사용자 학습 보조 — 사용자가 숙지 후 명시적 OFF).
        UserDefaults.standard.register(defaults: [
            "autoPasteEnabled": true,
            "clipsPerPage": 6,
            "autoFitClipListHeight": false,
            "hintBarVisible": true
        ])

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
            if defaults.object(forKey: Constants.clipboardCaptureEnabledKey) == nil { return true }
            return defaults.bool(forKey: Constants.clipboardCaptureEnabledKey)
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

        // ⑥ UI ViewModel (View lifetime 결속 — Composition Root에서 보관, View는 @Bindable로 접근)
        let clipsVM = ClipsViewModel(repository: grdbRepo, pasteService: pasteSvc, fileClipService: fcs, toastQueue: toastQ)
        // TASK-043 — toggleCapture 호출 시 watcher.setEnabled actor 메서드 호출 대상 주입.
        clipsVM.setClipboardWatcher(watcher)
        self.clipsViewModel = clipsVM
        let settingsVM = SettingsViewModel(loginItemService: self.loginItemService)
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
        let prefsController = PreferencesWindowController(viewModel: settingsVM)
        self.preferencesController = prefsController
        let popover = PopoverWindow(
            viewModel: clipsVM,
            settingsViewModel: settingsVM,  // TASK-054 fix-1 — windowWillResize 안에서 setClipsPerPage 직접 호출.
            onOpenSettings: { [prefsController] in prefsController.show() }
        )
        self.popoverWindow = popover
        self.statusItemController = StatusItemController(popoverWindow: popover)

        // ⑨ HotkeyMonitor callback 연결 — TASK-018 Phase 9 ⌘ hold *v1.0 보류* (onHoldStart/onHoldEnd 미연결). TASK-046 — ⌘ double-tap 트리거 폐기로 `onDoubleTap` 콜백 삭제. 방식 2 popover 호출 자체는 유지 — 트리거는 ⑨-2 SPM 단축키 (default `⌘⇧V`) 가 담당.
        // ⌘ hold 보류 사유: (a) 일반 ⌘+key 단축키 사용 중 의도 안 한 popover 오트리거 사용성 저해, (b) 방식 1/2 popover 열린 상태에서 단축키 입력 시 방식 3 진입으로 전환되어 사용성 저해. 코드 분기(`PopoverWindow.mode == .method3`)는 유지 (미래 부활 가능). 호출 사이트 X.
        let hotkeyMon = self.hotkeyMonitor
        hotkeyMon.onHoldStart = nil
        hotkeyMon.onHoldEnd = nil

        // ⑨-2 TASK-032 — KeyboardShortcuts SPM (Carbon RegisterEventHotKey 기반, Accessibility 권한 무관) 진입점 등록.
        // default ⌘⇧V — 사용자가 ShortcutsTab Recorder 로 변경하기 전 (getShortcut == nil 분기) 에만 박음 (사용자 변경 보존).
        // HotkeyMonitor (⌘ hold 영역, modifier-only 후킹, 권한 필수, TASK-018 Phase 9 보류) 와 별개 진입점 — 권한 거부 사용자도 popover 진입 가능. TASK-046 — 방식 2 popover 호출 트리거 단일화 (⌘ double-tap 트리거 폐기 후 SPM 단축키 통로만 / TASK-032 시점 ⌘⇧V SPM 을 *방식 4* 별도 진입점으로 잘못 분리 박은 명명도 본 task로 통합 정합 — 방식 4 폐기 + 방식 2 트리거 흡수).
        if KeyboardShortcuts.getShortcut(for: .popoverOpen) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .popoverOpen)
            Logger.hotkey.info("TASK-032 — popoverOpen default shortcut set: ⌘⇧V")
        }
        self.hotkeyManager.register(name: .popoverOpen) { [popover, clipsVM] in
            Task { @MainActor in
                Logger.hotkey.info("popoverOpen shortcut triggered (방식 2 — SPM)")
                await clipsVM.reload()
                popover.show(mode: .method2)
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
        Task {
            await watcher.start()
            Logger.appLifecycle.info("ClipboardWatcher started")
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

        // ⑪ Onboarding — 첫 실행 시 표시
        if !onboardingVM.hasCompleted {
            Task { @MainActor in
                Self.presentOnboarding(viewModel: onboardingVM)
            }
        }

        Logger.appLifecycle.info("StashApp init complete — all services wired")
    }

    @MainActor
    private static func presentOnboarding(viewModel: OnboardingViewModel) {
        let onboardingWindow = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: DesignTokens.WindowSize.onboardingWidth,
                height: 460
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.title = String(localized: "onboarding.welcome.title")
        onboardingWindow.center()
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.level = .modalPanel
        let hosting = NSHostingController(
            rootView: OnboardingWindow(
                viewModel: viewModel,
                onClose: { [weak onboardingWindow] in
                    onboardingWindow?.orderOut(nil)
                }
            )
        )
        onboardingWindow.contentViewController = hosting
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow.makeKeyAndOrderFront(nil)
    }

    var body: some Scene {
        // NOTE: MenuBarExtra 미사용 — 좌/우 클릭 분기 한계로 NSStatusItem 직접 사용 (ARCHITECTURE §9-2)
        // TASK-029 — SwiftUI Settings Scene 본문 비움. 자동 ⌘+, 메뉴 항목은 `.commands` `CommandGroup(replacing: .appSettings)` 가 PreferencesWindowController.show() 호출로 재등록 (마우스 클릭 / ⌘+, / ESC 단일 controller 경유).
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "preferences.row") + "...") {
                    preferencesController.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    // 전체 삭제 NSAlert 모달 제거 (디자인 popover.jsx 정합 — 즉시 실행 + 토스트). 검색바 안 "전체 삭제" 텍스트 버튼 또는 단축키 ⌥⌘⌫·⌘⇧⌫ 호출 시 ClipsViewModel.deleteAllExceptPinned() 즉시 실행.
}
