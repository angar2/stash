// PopoverWindow.computeOrigin 추출 helper 단위 테스트 — TASK-084 Phase 4a 안전망
// 세 분기 (panelMovedByUser / anchorFirstEntry / followUp) × 5 anchor × 화면 경계 clamp 매트릭스.
// 외부 시그니처 동일 + 동작 동일성 보장 강제 검증.
import Testing
import AppKit
@testable import stash

@Suite("PopoverWindow.computeOrigin — 매트릭스")
struct ComputeOriginTests {
    /// 일반 화면 visibleFrame (1280×800, origin=(0, 0)) — clamp 발생 X 영역 검증용.
    let standardVisible = NSRect(x: 0, y: 0, width: 1280, height: 800)

    // MARK: - panelMovedByUser 분기 (현재 origin.x 유지 + top 고정 + clamp)

    @Test("panelMovedByUser — top 고정 (prevTop - newHeight = newY)")
    func panelMovedByUserTopFixed() {
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)  // top = 700
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .panelMovedByUser,
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        #expect(newOrigin.x == 100)  // x 유지
        #expect(newOrigin.y == 500)  // 700 - 200 = 500 (top 고정)
    }

    @Test("panelMovedByUser — 화면 우측 clamp (x > maxX - width)")
    func panelMovedByUserClampRight() {
        let currentFrame = NSRect(x: 1000, y: 400, width: 380, height: 300)  // x=1000 → maxX-width=900 으로 clamp
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .panelMovedByUser,
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        #expect(newOrigin.x == 900)  // 1280 - 380 = 900
    }

    @Test("panelMovedByUser — 화면 좌측 clamp (x < minX)")
    func panelMovedByUserClampLeft() {
        let currentFrame = NSRect(x: -50, y: 400, width: 380, height: 300)
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .panelMovedByUser,
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        #expect(newOrigin.x == 0)  // minX clamp
    }

    @Test("panelMovedByUser — 화면 하단 clamp (y < minY)")
    func panelMovedByUserClampBottom() {
        // top=50, height=600 → y = 50-600 = -550 (clamp → 0)
        let currentFrame = NSRect(x: 100, y: -550, width: 380, height: 600)  // 이전 top = 50
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .panelMovedByUser,
            currentFrame: currentFrame,
            fittingHeight: 600,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        #expect(newOrigin.y == 0)  // minY clamp
    }

    // MARK: - followUp 분기 (panelMovedByUser 와 동일 흐름)

    @Test("followUp — panelMovedByUser 와 동일 (top 고정 + clamp)")
    func followUpSameAsMoved() {
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)
        let movedResult = PopoverWindow.computeOrigin(
            mode: .panelMovedByUser,
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        let followUpResult = PopoverWindow.computeOrigin(
            mode: .followUp,
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        #expect(movedResult.x == followUpResult.x)
        #expect(movedResult.y == followUpResult.y)
    }

    // MARK: - anchorFirstEntry 분기 × 5 anchor

    @Test("anchorFirstEntry topRight — top 고정 + x = maxX - width - inset")
    func anchorTopRight() {
        // prevTop = y + height = 400 + 300 = 700 — top 고정 시 newY = prevTop - fittingHeight = 700 - 200 = 500
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .anchorFirstEntry(anchor: .topRight, inset: 8),
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        let expectedX: CGFloat = 892  // = 1280 - 380 - 8
        let expectedY: CGFloat = 500
        #expect(newOrigin.x == expectedX)
        #expect(newOrigin.y == expectedY)
    }

    @Test("anchorFirstEntry bottomRight — bottom 고정 + anchor origin y")
    func anchorBottomRight() {
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .anchorFirstEntry(anchor: .bottomRight, inset: 8),
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        let expectedX: CGFloat = 892
        let expectedY: CGFloat = 8  // bottom 고정 — anchor origin.y (= visibleFrame.minY + inset)
        #expect(newOrigin.x == expectedX)
        #expect(newOrigin.y == expectedY)
    }

    @Test("anchorFirstEntry topLeft — top 고정 + x = minX + inset")
    func anchorTopLeft() {
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .anchorFirstEntry(anchor: .topLeft, inset: 8),
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        let expectedX: CGFloat = 8
        let expectedY: CGFloat = 500
        #expect(newOrigin.x == expectedX)
        #expect(newOrigin.y == expectedY)
    }

    @Test("anchorFirstEntry bottomLeft — bottom 고정 + x = minX + inset")
    func anchorBottomLeft() {
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .anchorFirstEntry(anchor: .bottomLeft, inset: 8),
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        let expectedX: CGFloat = 8
        let expectedY: CGFloat = 8
        #expect(newOrigin.x == expectedX)
        #expect(newOrigin.y == expectedY)
    }

    @Test("anchorFirstEntry center — center 고정 + anchor x = midX - width/2")
    func anchorCenter() {
        // prevMidY = y + height/2 = 400 + 150 = 550 — center 고정 시 newY = prevMidY - fittingHeight/2 = 550 - 100 = 450
        let currentFrame = NSRect(x: 100, y: 400, width: 380, height: 300)
        let newOrigin = PopoverWindow.computeOrigin(
            mode: .anchorFirstEntry(anchor: .center, inset: 0),
            currentFrame: currentFrame,
            fittingHeight: 200,
            preservedWidth: 380,
            visibleFrame: standardVisible
        )
        let expectedX: CGFloat = 450  // = 1280/2 - 380/2
        let expectedY: CGFloat = 450
        #expect(newOrigin.x == expectedX)
        #expect(newOrigin.y == expectedY)
    }
}
