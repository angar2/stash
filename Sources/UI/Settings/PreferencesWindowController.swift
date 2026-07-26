// 환경설정 윈도우 컨트롤러 — SwiftUI Settings Scene 대체 (TASK-029). 마우스 클릭 / ⌘+, / ESC 모든 진입점 단일 controller 경유.
import AppKit
import SwiftUI
import OSLog

@MainActor
final class PreferencesWindowController {
    private let viewModel: SettingsViewModel
    /// TASK-098 — 단축키 탭 `PIN 단축키` 묶음이 핀 항목의 명칭·값을 표시·수정하므로 클립 뷰모델을 함께 보관한다.
    private let clipsViewModel: ClipsViewModel
    private var window: PreferencesWindow?

    init(viewModel: SettingsViewModel, clipsViewModel: ClipsViewModel) {
        self.viewModel = viewModel
        self.clipsViewModel = clipsViewModel
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

    /// TASK-089 Phase 2 — XCUITest 격리용 헬퍼. UI 테스트 진입 시 윈도우를 primary screen 중앙 박음.
    /// 일반 사용자 흐름 호출 X — 다중 모니터 환경에서 background 앱 activate 시 active screen 임의 선택으로 윈도우가 화면 밖 박힐 수 있는 케이스 (XCUI hittable false) 회피.
    func recenterOnPrimaryScreenForUITest() {
        guard let target = window, let screen = NSScreen.screens.first else { return }
        let frame = target.frame
        let screenFrame = screen.visibleFrame
        target.setFrameOrigin(NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.midY - frame.height / 2 + 60
        ))
        Logger.ui.info("PreferencesWindowController.recenterOnPrimaryScreenForUITest — frame=\(NSStringFromRect(target.frame), privacy: .public)")
    }

    private func ensureWindow() -> PreferencesWindow {
        if let window { return window }
        let hosting = NSHostingController(rootView: SettingsWindow(viewModel: viewModel, clipsViewModel: clipsViewModel))
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
        newWindow.title = L10n("preferences.row")
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
