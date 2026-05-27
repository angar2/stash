// Onboarding 3단계 진행 + 건너뛰기 분기 시나리오 — Phase 3 (TASK-089)
import XCTest

final class OnboardingWindowTests: XCUITestBase {

    /// `--reset-onboarding` launch → onboarding 윈도우 표시 + 1단계 (welcome.next 버튼) 확인.
    func testOnboardingShowsWelcomeStep() {
        launchForUITest()
        waitForAppReady(seconds: 1.5)

        let nextButton = app.buttons["onboarding.welcome.next"]
        XCTAssertTrue(
            nextButton.waitForExistence(timeout: 5.0),
            "Onboarding 1단계 (welcome.next) 버튼 미표시"
        )
    }

    /// 1단계 (welcome) → 2단계 (permission) 전환 검증.
    func testOnboardingAdvancesToPermissionStep() {
        launchForUITest()
        waitForAppReady(seconds: 1.5)

        let welcomeNext = app.buttons["onboarding.welcome.next"]
        expectExists(welcomeNext, message: "welcome.next 미표시")
        welcomeNext.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 권한 미부여 분기 — openSystemSettings 버튼 표시.
        // (테스트 환경에서 권한이 부여되어 있을 수도 있음 — 둘 중 하나는 표시되어야 함.)
        let permissionOpen = app.buttons["onboarding.permission.openSystemSettings"]
        let permissionAdvance = app.buttons["onboarding.permission.advanceGranted"]
        let exists = permissionOpen.waitForExistence(timeout: 3.0)
            || permissionAdvance.waitForExistence(timeout: 1.0)
        XCTAssertTrue(exists, "Onboarding 2단계 (permission) 진입 후 권한 분기 버튼 미표시")
    }

    /// 1단계 → 2단계 → 3단계 (tutorial) → 완료 전체 플로우 검증.
    /// 권한 미부여 분기 — skip 버튼 경유.
    func testOnboardingFullSkipFlow() {
        launchForUITest()
        waitForAppReady(seconds: 1.5)

        // 1단계: welcome.next
        let welcomeNext = app.buttons["onboarding.welcome.next"]
        expectExists(welcomeNext, message: "welcome.next 미표시")
        welcomeNext.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 2단계: 권한 분기 — skip 또는 advanceGranted 모두 tutorial 진입.
        let permissionSkip = app.buttons["onboarding.permission.skip"]
        let permissionAdvance = app.buttons["onboarding.permission.advanceGranted"]
        if permissionSkip.waitForExistence(timeout: 3.0) {
            permissionSkip.click()
        } else if permissionAdvance.waitForExistence(timeout: 1.0) {
            permissionAdvance.click()
        } else {
            XCTFail("Onboarding 2단계 권한 분기 버튼 미표시")
            return
        }
        Thread.sleep(forTimeInterval: 0.5)

        // 3단계: tutorial.complete
        let tutorialComplete = app.buttons["onboarding.tutorial.complete"]
        XCTAssertTrue(
            tutorialComplete.waitForExistence(timeout: 5.0),
            "Onboarding 3단계 (tutorial.complete) 버튼 미표시"
        )
        tutorialComplete.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 완료 후 윈도우 dismiss — tutorial.complete 버튼이 사라져야 함.
        XCTAssertFalse(
            tutorialComplete.exists,
            "Onboarding 완료 후 tutorial.complete 버튼 잔존 (윈도우 미dismiss)"
        )
    }
}
