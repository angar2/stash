// NSWorkspace 활성 앱 노티 구독으로 frontmost 사용자 활성 앱 번들 ID 추적 (TASK-033 *저장하지 않을 앱* 백엔드 + TASK-040 클립 출처 박음 백엔드)
import Foundation
import AppKit
import OSLog

/// stash 자체 활성화 시 갱신 skip — *마지막 사용자 활성 앱* 유지.
/// 사용처 2건: (1) ClipboardWatcher.buildClip 차단 매칭 (TASK-033) / (2) ClipboardWatcher.buildClip 클립의 `sourceAppBundleId` 박음 (TASK-040).
@MainActor
final class FrontmostAppTracker: FrontmostAppTracking {
    private(set) var currentBundleId: String?
    private var observer: NSObjectProtocol?

    init() {
        self.currentBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleId = app.bundleIdentifier
            if bundleId != Bundle.main.bundleIdentifier {
                Task { @MainActor [weak self] in
                    self?.currentBundleId = bundleId
                    Logger.clipboard.debug("FrontmostAppTracker: \(bundleId ?? "nil", privacy: .public)")
                }
            }
        }
        Logger.clipboard.info("FrontmostAppTracker initialized — current=\(self.currentBundleId ?? "nil", privacy: .public)")
    }

    // 메뉴바 앱 (LSUIElement) — process termination 시 NotificationCenter 자동 정리. 별도 deinit 불필요 (Swift 6 strict concurrency `non-Sendable property in nonisolated deinit` 회피).
}
