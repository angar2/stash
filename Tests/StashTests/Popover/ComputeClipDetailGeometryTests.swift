// PopoverWindow.computeClipDetailGeometry 추출 helper 단위 테스트 — TASK-084 Phase 4b 안전망
// 핵심 분기 cover — zone .pin 방향 결정 / hasCopyLocation 분기 / 화면 경계 clamp / arrowOffsetY 보정.
import Testing
import AppKit
@testable import stash

@Suite("PopoverWindow.computeClipDetailGeometry — 핵심 분기")
struct ComputeClipDetailGeometryTests {
    /// 일반 화면 visibleFrame.
    let standardVisible = NSRect(x: 0, y: 0, width: 1280, height: 800)

    /// 화면 중앙 popover (380×400, x=450, y=200, top=600).
    let popoverCenterFrame = NSRect(x: 450, y: 200, width: 380, height: 400)

    @Test("hasCopyLocation true vs false — detailH 차이 (extraH 증가)")
    func hasCopyLocationAffectsDetailH() {
        let withoutLoc = PopoverWindow.computeClipDetailGeometry(
            zone: .clip,
            rowFrameInPopoverMidY: 100,
            anchorFrame: popoverCenterFrame,
            popoverFrame: popoverCenterFrame,
            pinSidebarFrame: nil,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 100,
            hasCopyLocation: false
        )
        let withLoc = PopoverWindow.computeClipDetailGeometry(
            zone: .clip,
            rowFrameInPopoverMidY: 100,
            anchorFrame: popoverCenterFrame,
            popoverFrame: popoverCenterFrame,
            pinSidebarFrame: nil,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 100,
            hasCopyLocation: true
        )
        // copy location block 이 박히면 detailH 가 더 커야 함.
        #expect(withLoc.detailH > withoutLoc.detailH)
        // 차이 = clipMetaLocationBlockHeight (DesignTokens 단일 진실 소스).
        #expect(withLoc.detailH - withoutLoc.detailH == DesignTokens.Spacing.clipMetaLocationBlockHeight)
    }

    @Test("zone=.pin + 사이드바 본체 좌측 → direction=.left")
    func pinZoneSidebarLeftDirection() {
        // 사이드바 (x=300) 가 본체 (x=450) 좌측 위치 → direction=.left.
        let sidebarFrame = NSRect(x: 300, y: 200, width: 100, height: 400)
        let geometry = PopoverWindow.computeClipDetailGeometry(
            zone: .pin,
            rowFrameInPopoverMidY: 100,
            anchorFrame: sidebarFrame,
            popoverFrame: popoverCenterFrame,
            pinSidebarFrame: sidebarFrame,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 200,
            hasCopyLocation: false
        )
        #expect(geometry.direction == .left)
    }

    @Test("zone=.pin + 사이드바 본체 우측 → direction=.right")
    func pinZoneSidebarRightDirection() {
        // 사이드바 (x=900) 가 본체 (x=450) 우측 위치 → direction=.right.
        let sidebarFrame = NSRect(x: 900, y: 200, width: 100, height: 400)
        let geometry = PopoverWindow.computeClipDetailGeometry(
            zone: .pin,
            rowFrameInPopoverMidY: 100,
            anchorFrame: sidebarFrame,
            popoverFrame: popoverCenterFrame,
            pinSidebarFrame: sidebarFrame,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 200,
            hasCopyLocation: false
        )
        #expect(geometry.direction == .right)
    }

    @Test("originX 화면 우측 clamp (totalW > maxX - originX)")
    func originXClampedRight() {
        // 본체 가 화면 우측 끝 직전 위치 → detail 우측 fallback 시도 시 화면 밖 → clamp.
        let popoverRightEdge = NSRect(x: 1200, y: 200, width: 80, height: 400)
        let geometry = PopoverWindow.computeClipDetailGeometry(
            zone: .clip,
            rowFrameInPopoverMidY: 100,
            anchorFrame: popoverRightEdge,
            popoverFrame: popoverRightEdge,
            pinSidebarFrame: nil,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 200,
            hasCopyLocation: false
        )
        let totalW = DesignTokens.WindowSize.clipDetailWidth + DesignTokens.Spacing.clipDetailArrowWidth
        let safe = DesignTokens.Spacing.clipDetailEdgeSafety
        let maxAllowedX = standardVisible.maxX - totalW - safe
        // originX 가 maxAllowedX 이하 보장.
        #expect(geometry.originX <= maxAllowedX)
    }

    @Test("originY 화면 상단 clamp + arrowOffsetY 보정")
    func originYClampedTopWithArrowAdjust() {
        // 본체 가 화면 상단 (y=750, height=40, top=790) — detailH > 50 시 originY = top 영역에서 maxY 초과 → clamp.
        let popoverTop = NSRect(x: 450, y: 750, width: 380, height: 40)
        let geometry = PopoverWindow.computeClipDetailGeometry(
            zone: .clip,
            rowFrameInPopoverMidY: 20,  // 본체 안 거의 center
            anchorFrame: popoverTop,
            popoverFrame: popoverTop,
            pinSidebarFrame: nil,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 200,  // 충분히 큰 raw content
            hasCopyLocation: false
        )
        let safe = DesignTokens.Spacing.clipDetailEdgeSafety
        let maxY = standardVisible.maxY - geometry.detailH - safe
        // clamp 영역 안 보장.
        #expect(geometry.originY <= maxY)
    }

    @Test("arrowOffsetY 가드 — [arrowH/2, detailH - arrowH/2] 범위 안")
    func arrowOffsetYWithinGuard() {
        let geometry = PopoverWindow.computeClipDetailGeometry(
            zone: .clip,
            rowFrameInPopoverMidY: 100,
            anchorFrame: popoverCenterFrame,
            popoverFrame: popoverCenterFrame,
            pinSidebarFrame: nil,
            screenVisibleFrame: standardVisible,
            rawContentHeight: 200,
            hasCopyLocation: true
        )
        let arrowH = DesignTokens.Spacing.clipDetailArrowHeight
        #expect(geometry.arrowOffsetY >= arrowH / 2)
        #expect(geometry.arrowOffsetY <= geometry.detailH - arrowH / 2)
    }
}
