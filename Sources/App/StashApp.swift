// @main 진입점 + Composition Root — 전체 의존성 와이어링 (ARCHITECTURE §7-2 / §9-4)
import SwiftUI
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
    let pasteService: PasteService

    init() {
        // ① Persistence — 가장 안쪽부터 (ARCHITECTURE §9-4 step 2-3)
        let dataFolder = AppDataPath.dataFolder()
        let dbPath = AppDataPath.databaseFile()
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        let grdbRepo: GRDBClipRepository
        do {
            grdbRepo = try GRDBClipRepository(dbPath: dbPath)
        } catch {
            Logger.database.error("DB init failed, removing and recreating: \(error)")
            try? FileManager.default.removeItem(at: dbPath)
            // 손상 파일 제거 후 재생성 — 실패하면 앱 시작 불가 (fatalError 허용)
            grdbRepo = try! GRDBClipRepository(dbPath: dbPath)
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
        self.pasteService = PasteService(
            synthesizer: CGEventPasteSynthesizer(),
            pasteboard: pb,
            repository: grdbRepo,
            permissionService: permSvc
        )

        // ⑤ Startup — async 작업은 Task로 위임 (ARCHITECTURE §9-4 step 8-9)
        Task {
            await watcher.start()
            Logger.appLifecycle.info("ClipboardWatcher started")
        }
        Task {
            await permSvc.recheck()
            Logger.appLifecycle.info("Initial permission check done")
        }

        Logger.appLifecycle.info("StashApp init complete — all services wired")
    }

    var body: some Scene {
        // NOTE: MenuBarExtra 미사용 — 좌/우 클릭 분기 한계로 NSStatusItem 직접 사용 (ARCHITECTURE §9-2)
        // StatusItemController 인스턴스화는 Stage 4 (UI) 에서 구현
        Settings {
            EmptyView()
        }
    }
}
