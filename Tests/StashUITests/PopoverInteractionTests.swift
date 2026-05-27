// Popover 표시 워크어라운드 + 시드 클립 인식 + 핵심 인터랙션 시나리오 — Phase 4 (TASK-089)
import XCTest

final class PopoverInteractionTests: XCUITestBase {

    /// `--show-popover --seed-clips=5` launch → popover panel (XCUI Dialog) + clipsArea (ScrollView) + clip 행 5건 표시 검증.
    /// 메뉴바 앱 (`LSUIElement=true`) + `nonactivatingPanel` 환경에서 XCUI hit testing 도달 가능 (워크어라운드 — `NSApp.activate` 호출 + accessibility identifier 명시).
    func testPopoverShowsSeededClips() {
        launchWithPopover(seedClips: 5)
        waitForAppReady(seconds: 2.0)

        // popover dialog 표시 검증.
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(
            dialog.waitForExistence(timeout: 5.0),
            "popover dialog 미표시 — popover 자체가 XCUI 인식 안 됨"
        )

        // clipsArea ScrollView 검증.
        let clipsArea = app.scrollViews["popover.clipsArea"]
        XCTAssertTrue(
            clipsArea.waitForExistence(timeout: 3.0),
            "popover.clipsArea (ScrollView) 미표시"
        )

        // 시드 클립 행 5건 — 각 row identifier 박힌 staticTexts 매칭.
        // 각 ClipRowView 안 텍스트는 *UITest seed clip #N* 패턴.
        for idx in 0..<5 {
            let rowTexts = app.staticTexts.matching(identifier: "popover.clip.row.\(idx)")
            XCTAssertGreaterThan(
                rowTexts.count, 0,
                "popover.clip.row.\(idx) 매칭 staticText 미존재"
            )
        }
    }

    /// 시드 0건 → clipsArea 표시되지만 clip 행 0건 (빈 상태).
    func testPopoverShowsEmptyState() {
        launchWithPopover(seedClips: 0)
        waitForAppReady(seconds: 2.0)

        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(
            dialog.waitForExistence(timeout: 5.0),
            "popover dialog 미표시 (빈 상태)"
        )

        // 빈 상태 — clip row 매칭 0건.
        let anyRow = app.staticTexts.matching(identifier: "popover.clip.row.0").count
        XCTAssertEqual(anyRow, 0, "시드 0건인데 clip.row.0 매칭 존재 — 빈 상태 회귀")
    }

    /// 시드 3건 → 정확히 3 row 표시. 4번째 row 미존재 검증.
    func testPopoverClipRowCount() {
        launchWithPopover(seedClips: 3)
        waitForAppReady(seconds: 2.0)

        let dialog = app.dialogs.firstMatch
        expectExists(dialog, message: "popover dialog 미표시")

        for idx in 0..<3 {
            let rowTexts = app.staticTexts.matching(identifier: "popover.clip.row.\(idx)")
            XCTAssertGreaterThan(
                rowTexts.count, 0,
                "popover.clip.row.\(idx) 매칭 staticText 미존재 (시드 3건 중)"
            )
        }
        // 4번째 row 미존재.
        let fourthRowCount = app.staticTexts.matching(identifier: "popover.clip.row.3").count
        XCTAssertEqual(fourthRowCount, 0, "시드 3건인데 clip.row.3 매칭 존재 — 회귀")
    }

    /// 검색 textField 표시 + 입력 → 매칭 클립 필터링 검증.
    func testPopoverSearchFilter() {
        launchWithPopover(seedClips: 5)
        waitForAppReady(seconds: 2.0)

        // 검색 textField — placeholderValue '검색' 또는 'Search'. firstMatch 충분.
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 5.0),
            "검색 textField 미표시"
        )

        // *seed clip #3* 매칭 검색 입력 — debounce 200ms + maxWait 500ms 대기.
        searchField.click()
        searchField.typeText("#3")
        Thread.sleep(forTimeInterval: 0.8)

        // 검색 결과 — *seed clip #3* 만 매칭 (총 1건). row.0 매칭 staticText 존재 + row.1 미존재 검증.
        let firstRowCount = app.staticTexts.matching(identifier: "popover.clip.row.0").count
        XCTAssertGreaterThan(firstRowCount, 0, "검색 결과 첫 row 미표시 (매칭 1건 기대)")

        let secondRowCount = app.staticTexts.matching(identifier: "popover.clip.row.1").count
        XCTAssertEqual(secondRowCount, 0, "검색 결과 2번째 row 잔존 — *#3* 단일 매칭 기대")
    }
}
