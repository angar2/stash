// Settings 4탭 ViewModel — Login Item 토글 / Paste 모드 / 차단 앱 / 데이터 폴더 액션 (UX-UI §4 정합)
import Foundation
import Observation
import AppKit
import OSLog

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - State
    var loginItemEnabled: Bool = false
    var pasteMode: PasteMode = .autoPaste
    var blockedAppBundleIds: [String] = []
    var shortcutConflictMessage: String?
    var accessibilityGranted: Bool = false  // PermissionService.statusPublisher 구독으로 갱신 (후속 task)

    private let loginItemService: LoginItemService

    init(loginItemService: LoginItemService) {
        self.loginItemService = loginItemService
        self.loginItemEnabled = (try? loginItemService.isEnabled) ?? false
        loadPasteMode()
        loadBlockedApps()
    }

    func updateAccessibilityGranted(_ granted: Bool) {
        self.accessibilityGranted = granted
    }

    // MARK: - Login Item
    func toggleLoginItem(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            loginItemEnabled = enabled
        } catch {
            Logger.ui.error("LoginItem toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Paste mode
    func setPasteMode(_ mode: PasteMode) {
        pasteMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "pasteMode")
    }

    private func loadPasteMode() {
        if let raw = UserDefaults.standard.string(forKey: "pasteMode"),
           let mode = PasteMode(rawValue: raw) {
            pasteMode = mode
        }
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
}
