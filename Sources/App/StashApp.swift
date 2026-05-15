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
    let method2Window: Method2Window
    let method3Window: Method3Window
    let toastQueue: ToastQueue
    let toastWindowController: ToastWindowController
    let permissionToastNotifier: PermissionToastNotifier

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

        // ④ 도메인 Service — 생성자 주입 (ARCHITECTURE §9-4 step 5)
        let watcher = ClipboardWatcher(
            pasteboard: pb,
            fileClipService: fcs,
            repository: grdbRepo
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
            permissionService: permSvc
        )
        self.pasteService = pasteSvc

        // ⑤ ToastQueue + ToastWindow (모든 ViewModel에서 발행)
        let toastQ = ToastQueue()
        self.toastQueue = toastQ
        self.toastWindowController = ToastWindowController(queue: toastQ)

        // ⑥ UI ViewModel (View lifetime 결속 — Composition Root에서 보관, View는 @Bindable로 접근)
        let clipsVM = ClipsViewModel(repository: grdbRepo, pasteService: pasteSvc, toastQueue: toastQ)
        self.clipsViewModel = clipsVM
        let settingsVM = SettingsViewModel(loginItemService: self.loginItemService)
        self.settingsViewModel = settingsVM
        let onboardingVM = OnboardingViewModel(permissionService: permSvc)
        self.onboardingViewModel = onboardingVM

        // ⑥-2 FrontmostAppTracker 즉시 초기화 — 앱 lifetime 내내 직전 frontmost 앱을 추적해 paste 시 destination 복원에 사용 (TASK-016 Bug 5 fix v3).
        _ = FrontmostAppTracker.shared

        // ⑦ Permission 토스트 + 시스템 알림 발행자
        self.permissionToastNotifier = PermissionToastNotifier(
            publisher: permSvc.statusPublisher,
            toastQueue: toastQ,
            notificationService: self.notificationService
        )

        // ⑧ UI controllers (NSStatusItem retain) — HistoryPopover 호스팅
        self.statusItemController = StatusItemController(
            permissionStatusPublisher: permSvc.statusPublisher,
            clipsViewModel: clipsVM,
            onOpenSettings: { Self.openSettings() }
        )
        let m2 = Method2Window(viewModel: clipsVM)
        let m3 = Method3Window(
            viewModel: clipsVM,
            onOpenSettings: { Self.openSettings() }
        )
        self.method2Window = m2
        self.method3Window = m3

        // ⑨ HotkeyMonitor callback 연결 — 방식 2/3 진입
        let hotkeyMon = self.hotkeyMonitor
        hotkeyMon.onHoldStart = { [m2, clipsVM] in
            Task { @MainActor in
                await clipsVM.reload()
                m2.show()
            }
        }
        hotkeyMon.onHoldEnd = { [m2] in m2.hide() }
        hotkeyMon.onDoubleTap = { [m3, clipsVM] in
            Task { @MainActor in
                await clipsVM.reload()
                m3.show()
            }
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
