// Settings 윈도우 5탭 전환 + 핵심 인터랙션 시나리오 — Phase 2 (TASK-089)
import XCTest

final class SettingsWindowTests: XCUITestBase {

    /// `--show-settings` launch 후 settings 윈도우 + 5 탭 버튼 모두 표시 검증.
    func testSettingsWindowDisplaysAllTabs() {
        launchWithSettings()
        waitForAppReady(seconds: 1.5)

        let tabs = ["general", "display", "shortcuts", "collection", "about"]
        for tab in tabs {
            let tabButton = app.buttons["settings.tab.\(tab)"]
            XCTAssertTrue(
                tabButton.waitForExistence(timeout: 3.0),
                "settings.tab.\(tab) 버튼 표시되어야 함"
            )
        }
    }

    /// About 탭 진입 시 *Stash* + version 텍스트 표시 검증.
    func testAboutTabShowsAppNameAndVersion() {
        launchWithSettings()
        waitForAppReady(seconds: 1.5)

        let aboutTab = app.buttons["settings.tab.about"]
        expectExists(aboutTab, message: "About 탭 버튼 미표시")
        aboutTab.click()
        // 탭 전환 동기 보장 — body 재평가 대기.
        Thread.sleep(forTimeInterval: 0.5)

        let appName = app.staticTexts["about.appName"]
        XCTAssertTrue(
            appName.waitForExistence(timeout: 3.0),
            "about.appName (Stash) 텍스트 미표시"
        )

        let version = app.staticTexts["about.version"]
        XCTAssertTrue(
            version.waitForExistence(timeout: 3.0),
            "about.version 텍스트 미표시"
        )
        // SwiftUI Text(.accessibilityIdentifier) 는 .label property 가 항상 박히는 게 X — element 존재로만 검증.
    }

    /// 5 탭 순차 클릭 — 각 탭 진입 후 다음 탭 진입 가능 검증 (탭 전환 자체 PASS).
    func testTabSwitchingCycle() {
        launchWithSettings()
        waitForAppReady(seconds: 1.5)

        let tabs = ["general", "display", "shortcuts", "collection", "about"]
        for tab in tabs {
            let tabButton = app.buttons["settings.tab.\(tab)"]
            expectExists(tabButton, message: "탭 \(tab) 미존재")
            tabButton.click()
            Thread.sleep(forTimeInterval: 0.3)
            // 클릭 후 탭 버튼 자체는 그대로 존재해야 함 (사라지면 회귀).
            XCTAssertTrue(tabButton.exists, "탭 \(tab) 클릭 후 버튼 사라짐 — 회귀")
        }
    }
}
