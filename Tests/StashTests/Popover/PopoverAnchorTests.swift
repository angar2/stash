// PopoverAnchor.origin 5종 anchor 위치 계산 단위 테스트 (TASK-054)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverAnchor.origin (TASK-054)")
struct PopoverAnchorTests {

    private let panelSize = NSSize(width: 380, height: 520)
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("TASK-054 — bottomRight origin = (maxX - w, minY)")
    func bottomRight() {
        let o = PopoverAnchor.bottomRight.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: 0)
        #expect(o.x == 1540, "bottomRight x = 1920 - 380 = 1540, got \(o.x)")
        #expect(o.y == 0, "bottomRight y = minY = 0, got \(o.y)")
    }

    @Test("TASK-054 — bottomLeft origin = (minX, minY)")
    func bottomLeft() {
        let o = PopoverAnchor.bottomLeft.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: 0)
        #expect(o.x == 0)
        #expect(o.y == 0)
    }

    @Test("TASK-054 — topLeft origin = (minX, maxY - h)")
    func topLeft() {
        let o = PopoverAnchor.topLeft.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: 0)
        #expect(o.x == 0)
        #expect(o.y == 560, "topLeft y = 1080 - 520 = 560, got \(o.y)")
    }

    @Test("TASK-054 — topRight origin = (maxX - w, maxY - h)")
    func topRight() {
        let o = PopoverAnchor.topRight.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: 0)
        #expect(o.x == 1540)
        #expect(o.y == 560)
    }

    @Test("TASK-054 — center origin = (midX - w/2, midY - h/2)")
    func center() {
        let o = PopoverAnchor.center.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: 0)
        #expect(o.x == 770, "center x = 960 - 190 = 770, got \(o.x)")
        #expect(o.y == 280, "center y = 540 - 260 = 280, got \(o.y)")
    }

    @Test("TASK-054 — bottomRight inset 8 적용 → (maxX - w - 8, minY + 8)")
    func bottomRightWithInset() {
        let o = PopoverAnchor.bottomRight.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: 8)
        #expect(o.x == 1532, "bottomRight x with inset = 1540 - 8 = 1532, got \(o.x)")
        #expect(o.y == 8, "bottomRight y with inset = 0 + 8 = 8, got \(o.y)")
    }

    @Test("TASK-054 — 다중 디스플레이 시뮬레이션 (visibleFrame minX/minY 비-0) origin 정합")
    func nonZeroVisibleFrameOrigin() {
        let offsetVisible = NSRect(x: 1920, y: 100, width: 2560, height: 1440)
        let o = PopoverAnchor.bottomRight.origin(panelSize: panelSize, visibleFrame: offsetVisible, inset: 0)
        #expect(o.x == 4100, "다중 디스플레이 우하단 x = 1920 + 2560 - 380 = 4100")
        #expect(o.y == 100, "다중 디스플레이 우하단 y = visibleMinY")
    }

    @Test("TASK-054 — `default` static = .bottomRight")
    func defaultAnchor() {
        #expect(PopoverAnchor.default == .bottomRight)
    }

    @Test("TASK-054 — CaseIterable allCases 5종 + rawValue 일관성")
    func allCases() {
        #expect(PopoverAnchor.allCases.count == 5)
        #expect(PopoverAnchor(rawValue: "bottomRight") == .bottomRight)
        #expect(PopoverAnchor(rawValue: "center") == .center)
        #expect(PopoverAnchor(rawValue: "invalid") == nil)
    }
}
