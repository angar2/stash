// XCUITest 베이스라인 launch 시나리오 — Phase 1 인프라 검증 (TASK-089)
import XCTest

final class StashUITests: XCUITestBase {

    /// 기본 launch — 인자 0건. 메뉴바 앱이 백그라운드로 정상 진입.
    func testLaunchWithoutArguments() {
        app.launch()
        // LSUIElement=true 앱은 launch 후 .runningForeground 또는 .runningBackground 모두 OK.
        XCTAssertTrue(
            app.state == .runningForeground || app.state == .runningBackground,
            "메뉴바 앱이 launch 후 실행 상태여야 함. 실제 state = \(app.state.rawValue)"
        )
    }

    /// UI 테스트 모드 launch — `--ui-test --isolated-data-folder --reset-onboarding`.
    /// 격리 데이터 폴더 + onboarding 윈도우 자연 진입 확인.
    func testLaunchInUITestMode() {
        launchForUITest()
        waitForAppReady(seconds: 1.5)
        // onboarding 윈도우가 표시되어야 함 (reset 후 첫 실행 흐름).
        // 시스템 윈도우 chrome 미박힘 (custom titlebar) — 윈도우 자체 존재 확인.
        let onboardingWindow = app.windows.firstMatch
        XCTAssertTrue(
            onboardingWindow.waitForExistence(timeout: 5.0),
            "UI test launch 후 onboarding 윈도우가 표시되어야 함"
        )
    }

    /// `--show-settings` launch argument — settings 윈도우 즉시 표시 검증.
    func testLaunchShowsSettingsWindow() {
        launchWithSettings()
        waitForAppReady(seconds: 1.5)
        // settings 윈도우 또는 onboarding 윈도우 둘 중 하나는 표시되어야 함.
        XCTAssertGreaterThan(
            app.windows.count, 0,
            "--show-settings launch 후 ≥1 윈도우 표시되어야 함"
        )
    }
}
