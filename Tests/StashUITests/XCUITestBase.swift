// XCUITest 공통 베이스 — 메뉴바 앱 launch + launch argument 헬퍼 (TASK-089 Phase 1)
import XCTest

/// XCUITest 통합 테스트 공통 베이스 — `LSUIElement=true` 앱 launch 패턴 + launch argument 매핑 + 격리 환경.
///
/// 메뉴바 앱 (`LSUIElement=true`) 은 Dock/메뉴바 미박힘 → XCUIApplication launch 시 *기본 윈도우 미박힘*.
/// 테스트가 윈도우를 보려면 `--show-popover` / `--show-settings` 같은 launch argument 로 명시적 진입 트리거.
class XCUITestBase: XCTestCase {

    /// 매 테스트 인스턴스마다 새 XCUIApplication. teardown 에서 종료.
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        if app?.state == .runningForeground || app?.state == .runningBackground {
            app.terminate()
        }
        app = nil
        super.tearDown()
    }

    // MARK: - Launch 헬퍼

    /// UI 테스트 launch — 기본 `--ui-test --isolated-data-folder --reset-onboarding` 박힘 + 추가 인자 변동.
    /// - Parameter extra: 추가 launch argument (예: `["--show-popover", "--seed-clips=5"]`).
    @discardableResult
    func launchForUITest(extra: [String] = []) -> XCUIApplication {
        let baseArgs = [
            "--ui-test",
            "--isolated-data-folder",
            "--reset-onboarding"
        ]
        app.launchArguments = baseArgs + extra
        app.launch()
        return app
    }

    /// popover 시나리오용 launch — seed clips + popover 즉시 표시.
    @discardableResult
    func launchWithPopover(seedClips: Int = 5) -> XCUIApplication {
        return launchForUITest(extra: [
            "--show-popover",
            "--seed-clips=\(seedClips)"
        ])
    }

    /// settings 시나리오용 launch — settings 윈도우 즉시 표시.
    @discardableResult
    func launchWithSettings() -> XCUIApplication {
        return launchForUITest(extra: ["--show-settings"])
    }

    // MARK: - 시간 헬퍼

    /// 짧은 sleep — 메뉴바 앱 popover/window 표시 동기 보장용. XCUI element 폴링 전 init 부수 작업 완료 대기.
    func waitForAppReady(seconds: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// element 가 일정 시간 안 존재할 때까지 대기. 실패 시 XCTFail.
    func expectExists(_ element: XCUIElement, timeout: TimeInterval = 5.0, message: String = "") {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, message.isEmpty ? "element 미존재: \(element)" : message)
    }
}
