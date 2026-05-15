// 직전 frontmost 앱을 항상 추적하는 글로벌 헬퍼 — paste 시 destination 앱 활성화 복원에 사용 (TASK-016 Bug 5 fix v3)
// stash NSStatusItem 클릭 시점에 stash가 frontmost가 되어 NSWorkspace.shared.frontmostApplication을 그 시점에 읽으면 stash 자신이라 이전 앱 정보가 사라짐.
// NSWorkspace.didActivateApplicationNotification을 앱 lifetime 내내 추적해 *직전* 앱을 항상 보관하면 popover show 시점에도 사용자 작업 앱 정보 유지.
import AppKit
import OSLog

@MainActor
final class FrontmostAppTracker {
    static let shared = FrontmostAppTracker()

    /// stash가 frontmost가 되기 *직전*에 활성이었던 앱. paste 시 활성화 복원 대상.
    private(set) var previousApp: NSRunningApplication?

    /// 현재 frontmost로 추적된 앱 (stash가 활성화된 동안에는 stash 직전 사용자 앱이 그대로 보관됨).
    private var currentApp: NSRunningApplication?

    private let bundleId = Bundle.main.bundleIdentifier

    private init() {
        currentApp = NSWorkspace.shared.frontmostApplication
        previousApp = currentApp  // 초기값 — stash 시작 시점 frontmost가 곧 직전 앱
        // userInfo에서 bundleId만 추출해 String으로 캡처 (Notification 자체를 Task로 넘기면 Sendable 위반).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notif in
            let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                FrontmostAppTracker.shared.handleActivation(app)
            }
        }
        Logger.appLifecycle.info("FrontmostAppTracker initialized — currentApp=\(self.currentApp?.bundleIdentifier ?? "nil", privacy: .public)")
    }

    private func handleActivation(_ activated: NSRunningApplication?) {
        guard let activated else { return }
        // stash 자신의 활성화는 previousApp 갱신 대상 X — currentApp만 유지
        if activated.bundleIdentifier == bundleId {
            Logger.ui.info("FrontmostAppTracker: stash activated — previousApp 보존 (\(self.previousApp?.bundleIdentifier ?? "nil", privacy: .public))")
            return
        }
        // 다른 앱이 활성화 — currentApp을 previousApp으로 밀고 새 앱을 currentApp으로
        previousApp = currentApp
        currentApp = activated
        Logger.ui.info("FrontmostAppTracker: \(activated.bundleIdentifier ?? "unknown", privacy: .public) activated — previousApp=\(self.previousApp?.bundleIdentifier ?? "nil", privacy: .public)")
    }
}
