// 환경설정 윈도우 컨트롤러 — SwiftUI Settings Scene 대체 (TASK-029). 마우스 클릭 / ⌘+, / ESC 모든 진입점 단일 controller 경유.
import AppKit
import SwiftUI
import OSLog

@MainActor
final class PreferencesWindowController {
    private let viewModel: SettingsViewModel
    private var window: PreferencesWindow?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    /// 마우스 클릭 / ⌘+, 통합 진입점. 윈도우 lazy 생성 + activate + frontmost 진입.
    /// LSUIElement=true background app 이라 `NSApp.activate(ignoringOtherApps:)` 우선 호출 필수 — SwiftUI Settings Scene 의 lazy 윈도우 컨트롤러가 popover panel context 에서 selector 라우팅 실패하는 1차 구현 root cause 회피.
    func show() {
        Logger.ui.info("PreferencesWindowController.show — activate + makeKeyAndOrderFront")
        let target = ensureWindow()
        if !target.isVisible {
            target.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        target.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> PreferencesWindow {
        if let window { return window }
        let hosting = NSHostingController(rootView: SettingsWindow(viewModel: viewModel))
        // NSHostingController 가 SwiftUI 의 intrinsic preferred content size 를 따라 NSWindow 자동 사이즈 조정.
        // 박지 않으면 윈도우 contentRect 가 SwiftUI view 를 채우지 못해 tab bar 만 fit 되고 ScrollView 영역이 0 으로 collapse 됨 (사용자 검수 발견).
        hosting.sizingOptions = [.preferredContentSize]
        let newWindow = PreferencesWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: DesignTokens.WindowSize.settingsWidth,
                height: DesignTokens.WindowSize.settingsContentMaxH + 80
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = String(localized: "preferences.row")
        newWindow.contentViewController = hosting
        newWindow.isReleasedWhenClosed = false
        self.window = newWindow
        return newWindow
    }
}

/// ESC 키 닫기 처리용 `NSWindow` subclass. `cancelOperation(_:)` 은 macOS 표준 ESC 액션 — 기본 NSWindow 는 응답 X 라 override 로 명시 처리.
final class PreferencesWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        Logger.ui.info("PreferencesWindow.cancelOperation — ESC pressed, orderOut")
        orderOut(nil)
    }
}
