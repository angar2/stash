// 클립 상세 sub-window + 핀 사이드바 좌/우 방향 결정 헬퍼 단위 테스트 (TASK-055)
import Testing
import CoreGraphics
@testable import stash

@Suite("ClipDetailDirection")
struct ClipDetailDirectionTests {

    /// 좌측 통과 — 본체 popover 가 화면 가운데 부근, sub-panel 폭이 좌측 가용 영역 안.
    @Test("TASK-055 — 좌측 통과 케이스: 좌측 가용 영역 충분 → .left")
    func leftPasses() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 500, y: 300, width: 380, height: 520)
        let direction = ClipDetailDirection.resolve(
            anchorFrame: anchor,
            totalWidth: 248,
            gap: 2,
            safe: 8,
            visibleFrame: visible
        )
        #expect(direction == .left)
    }

    /// 좌측 막힘 + 우측 통과 — 본체 popover 가 화면 좌측 끝에 박혀 있어 좌측 가용 영역 부족.
    @Test("TASK-055 — 좌측 막힘 우측 통과: 우측 fallback → .right")
    func leftBlockedRightPasses() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // anchor.minX = 100 — 좌측 originX = 100 - 2 - 248 = -150 (visible.minX 0 + safe 8 = 8 미달)
        let anchor = CGRect(x: 100, y: 300, width: 380, height: 520)
        let direction = ClipDetailDirection.resolve(
            anchorFrame: anchor,
            totalWidth: 248,
            gap: 2,
            safe: 8,
            visibleFrame: visible
        )
        #expect(direction == .right)
    }

    /// 양쪽 막힘 — 화면 폭이 매우 좁아 좌측 우측 모두 sub-panel 폭 안 들어감.
    @Test("TASK-055 — 양쪽 막힘: .left 강제 (화면 밖 픽셀 허용)")
    func bothBlocked() {
        // 화면 폭 600. anchor 가 폭 380 으로 화면 중앙 대부분 점유. 좌측 originX 음수, 우측 끝 좌표 초과.
        let visible = CGRect(x: 0, y: 0, width: 600, height: 900)
        let anchor = CGRect(x: 100, y: 300, width: 380, height: 520)
        let direction = ClipDetailDirection.resolve(
            anchorFrame: anchor,
            totalWidth: 248,
            gap: 2,
            safe: 8,
            visibleFrame: visible
        )
        #expect(direction == .left)
    }

    /// 핀 사이드바 anchorFrame 케이스 — 본체 popover 가 화면 우측 끝에 박혀 핀 사이드바도 좌측 막힘 시 우측 fallback.
    @Test("TASK-055 — 핀 사이드바 anchor: 본체 화면 우측 끝 + 사이드바 폭 220 → .right")
    func pinSidebarRightFallback() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // anchor.minX = 4 — 좌측 originX = 4 - 2 - 220 = -218 (visible.minX 0 + safe 8 미달)
        // 우측 끝 = 4 + 380 + 2 + 220 = 606 (visible.maxX 1440 - safe 8 = 1432 미만 → 통과)
        let popoverFrame = CGRect(x: 4, y: 100, width: 380, height: 520)
        let direction = ClipDetailDirection.resolve(
            anchorFrame: popoverFrame,
            totalWidth: 220, // pinSidebarWidth
            gap: 2,
            safe: 8,
            visibleFrame: visible
        )
        #expect(direction == .right)
    }

    /// originX 헬퍼 — .left / .right 각각 anchor 기반 좌표 산출 정확성.
    @Test("TASK-055 — originX 헬퍼: .left 좌표")
    func originXLeft() {
        let anchor = CGRect(x: 500, y: 300, width: 380, height: 520)
        let x = ClipDetailDirection.left.originX(anchorFrame: anchor, totalWidth: 248, gap: 2)
        #expect(x == CGFloat(250))  // 500 - 2 - 248
    }

    @Test("TASK-055 — originX 헬퍼: .right 좌표")
    func originXRight() {
        let anchor = CGRect(x: 500, y: 300, width: 380, height: 520)
        let x = ClipDetailDirection.right.originX(anchorFrame: anchor, totalWidth: 248, gap: 2)
        #expect(x == CGFloat(882))  // 500 + 380 + 2
    }
}
