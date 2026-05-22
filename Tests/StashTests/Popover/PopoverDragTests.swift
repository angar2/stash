// PopoverPanel.validateSavedOrigin — 저장 좌표 유효성 검증 단위 테스트 (TASK-054)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverPanel.validateSavedOrigin (TASK-054 이전 위치 기억하기)")
struct PopoverDragTests {

    private let panelSize = NSSize(width: 380, height: 520)
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("TASK-054 — 정상 좌표 (100, 100) → 유효")
    func validInteriorOrigin() {
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 100, y: 100), panelSize: panelSize, visibleFrame: visibleFrame)
        #expect(ok)
    }

    @Test("TASK-054 — 정확 우하단 (1540, 0) → 유효")
    func validBottomRightCorner() {
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 1540, y: 0), panelSize: panelSize, visibleFrame: visibleFrame)
        #expect(ok)
    }

    @Test("TASK-054 — x 가 visible 우측 초과 (1900, 0) → 무효 (panel 우측 화면 밖)")
    func invalidXBeyondRight() {
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 1900, y: 0), panelSize: panelSize, visibleFrame: visibleFrame)
        #expect(!ok, "x + w = 1900+380 = 2280 > maxX=1920")
    }

    @Test("TASK-054 — y 가 visible 상단 초과 (0, 800) → 무효 (panel 상단 화면 밖)")
    func invalidYBeyondTop() {
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 0, y: 800), panelSize: panelSize, visibleFrame: visibleFrame)
        #expect(!ok, "y + h = 800+520 = 1320 > maxY=1080")
    }

    @Test("TASK-054 — 음수 x (-10, 100) → 무효 (visible 좌측 미달)")
    func invalidNegativeX() {
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: -10, y: 100), panelSize: panelSize, visibleFrame: visibleFrame)
        #expect(!ok)
    }

    @Test("TASK-054 — 음수 y (0, -10) → 무효 (visible 하단 미달)")
    func invalidNegativeY() {
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 0, y: -10), panelSize: panelSize, visibleFrame: visibleFrame)
        #expect(!ok)
    }

    @Test("TASK-054 — panelSize 가 visibleFrame 초과 시 모든 좌표 무효 (작은 모니터)")
    func panelLargerThanVisible() {
        let smallVisible = NSRect(x: 0, y: 0, width: 100, height: 100)
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 0, y: 0), panelSize: panelSize, visibleFrame: smallVisible)
        #expect(!ok, "panelSize 380x520 > visible 100x100 — 화면 cap fail")
    }

    @Test("TASK-054 — 다중 디스플레이 시뮬레이션 visible offset 정합")
    func multiDisplayValid() {
        let offsetVisible = NSRect(x: 1920, y: 100, width: 2560, height: 1440)
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 2000, y: 200), panelSize: panelSize, visibleFrame: offsetVisible)
        #expect(ok, "두 번째 모니터 안 좌표 유효")
    }

    @Test("TASK-054 — 다중 디스플레이 첫 모니터 좌표가 두 번째 모니터 visibleFrame 기준 검사 시 무효 (모니터 분리 시뮬레이션)")
    func multiDisplayDisconnected() {
        let secondMonitorVisible = NSRect(x: 1920, y: 100, width: 2560, height: 1440)
        // 첫 모니터 (0~1920) 에 저장된 좌표가 두 번째 모니터 visible 기준이라 화면 밖.
        let ok = PopoverPanel.validateSavedOrigin(origin: NSPoint(x: 100, y: 100), panelSize: panelSize, visibleFrame: secondMonitorVisible)
        #expect(!ok, "원래 첫 모니터 좌표 (100,100) 가 두 번째 모니터 visibleFrame (minX=1920) 기준 좌측 미달")
    }

    // MARK: - TASK-054 fix-1 validateSavedFrame (origin + size 통합 검증)

    @Test("TASK-054 fix-1 — validateSavedFrame: 정상 origin + size → 유효")
    func validateSavedFrameValid() {
        let ok = PopoverPanel.validateSavedFrame(
            origin: NSPoint(x: 100, y: 100),
            size: NSSize(width: 400, height: 520),
            visibleFrame: visibleFrame
        )
        #expect(ok)
    }

    @Test("TASK-054 fix-1 — validateSavedFrame: size width 가 visibleFrame 초과 → 무효")
    func validateSavedFrameWidthOverflow() {
        let ok = PopoverPanel.validateSavedFrame(
            origin: NSPoint(x: 0, y: 0),
            size: NSSize(width: 2000, height: 520),
            visibleFrame: visibleFrame
        )
        #expect(!ok, "width 2000 > visibleFrame.width 1920")
    }

    @Test("TASK-054 fix-1 — validateSavedFrame: origin + size 가 visibleFrame 우측 초과 → 무효")
    func validateSavedFrameRightOverflow() {
        let ok = PopoverPanel.validateSavedFrame(
            origin: NSPoint(x: 1600, y: 0),
            size: NSSize(width: 400, height: 520),
            visibleFrame: visibleFrame
        )
        #expect(!ok, "1600 + 400 = 2000 > maxX=1920")
    }

    @Test("TASK-054 fix-1 — validateSavedFrame: 사용자가 박은 width 가 popoverWidth cap 안 (280~600) 인 케이스 유효")
    func validateSavedFrameWidthCustom() {
        let ok = PopoverPanel.validateSavedFrame(
            origin: NSPoint(x: 100, y: 100),
            size: NSSize(width: 600, height: 520),
            visibleFrame: visibleFrame
        )
        #expect(ok, "width 600 = popoverWidthMax 정합")
    }
}
