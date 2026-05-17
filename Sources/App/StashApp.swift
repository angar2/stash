// @main 진입점 + Composition Root — 전체 의존성 와이어링 (ARCHITECTURE §7-2 / §9-4)
import SwiftUI
import AppKit
import Combine
import OSLog

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
    let toastQueue: ToastQueue
    let toastWindowController: ToastWindowController
    let permissionToastNotifier: PermissionToastNotifier
    /// 권한 변경 시 hotkeyMonitor 자동 start/stop — App lifetime 보관 (구독 유지).
    let permissionMonitorBridge: AnyCancellable
    /// NSWorkspace 앱 활성화 감지 시 권한 recheck — 사용자가 시스템 설정에서 권한 부여 후 다른 앱으로 돌아올 때 자동 감지 (TASK-017 fix-3).
    let permissionRefresherObserver: NSObjectProtocol

    init() {
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
        let watcher = ClipboardWatcher(
            pasteboard: pb,
            fileClipService: fcs,
            repository: grdbRepo,
            // TASK-026 — 임계 초과 / 부분 실패 시 인앱 토스트 dispatch.
            onUserMessage: { msg in
                await MainActor.run {
                    toastQ.enqueue(.warn, msg)
                }
            }
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
        let clipsVM = ClipsViewModel(repository: grdbRepo, pasteService: pasteSvc, toastQueue: toastQ)
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
        let popover = PopoverWindow(
            viewModel: clipsVM,
            onOpenSettings: { Self.openSettings() }
        )
        self.popoverWindow = popover
        self.statusItemController = StatusItemController(
            permissionStatusPublisher: permSvc.statusPublisher,
            popoverWindow: popover
        )

        // ⑨ HotkeyMonitor callback 연결 — 새 방식 2 (⌘ double-tap) 진입만 연결.
        // TASK-018 Phase 9 — 새 방식 3 (⌘ hold) v1.0 *보류*. 사유: (a) 일반 ⌘+key 단축키 사용 중 의도 안 한 popover 오트리거 사용성 저해, (b) 방식 1/2 popover 열린 상태에서 단축키 입력 시 방식 3 진입으로 전환되어 사용성 저해. 코드 분기(`PopoverWindow.mode == .method3`)는 유지 (미래 부활 가능). onHoldStart/onHoldEnd 콜백 미연결 = 호출 사이트 X.
        let hotkeyMon = self.hotkeyMonitor
        hotkeyMon.onHoldStart = nil
        hotkeyMon.onHoldEnd = nil
        hotkeyMon.onDoubleTap = { [popover, clipsVM] in
            Task { @MainActor in
                await clipsVM.reload()
                popover.show(mode: .method2)
            }
        }

        // ⑨-2 권한 변경 시 hotkeyMonitor 자동 재시작 + ViewModel state 동기 (TASK-017 Phase 2-A / TASK-024) —
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

        // ⑨-3 권한 변경 감지 트리거 (TASK-017 fix-3) — stash는 LSUIElement=true (메뉴바 상주)라 background.
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
        Settings {
            SettingsWindow(viewModel: settingsViewModel)
        }
    }

    @MainActor
    private static func openSettings() {
        // Phase 7에서 본 구현 — 현 placeholder는 NSWorkspace 알림만
        Logger.ui.info("Open settings requested — Phase 7에서 본 구현")
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // 전체 삭제 NSAlert 모달 제거 (디자인 popover.jsx 정합 — 즉시 실행 + 토스트). 검색바 안 "전체 삭제" 텍스트 버튼 또는 단축키 ⌥⌘⌫·⌘⇧⌫ 호출 시 ClipsViewModel.deleteAllExceptPinned() 즉시 실행.
}
