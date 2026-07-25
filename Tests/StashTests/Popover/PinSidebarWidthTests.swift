// Pin 사이드바 너비 리사이즈 순수 로직 단위 테스트 (TASK-097 — clamp / 저장복원 / origin 불변 / 높이 고정)
import Testing
import CoreGraphics
import AppKit
@testable import stash

@MainActor
@Suite("Pin 사이드바 너비 리사이즈 (TASK-097)")
struct PinSidebarWidthTests {

    // MARK: clamp — [180, 400]

    @Test("clampPinSidebarWidth — 하한 미만 → 180 / 범위 내 → 그대로 / 상한 초과 → 400")
    func clampBounds() {
        #expect(PopoverWindow.clampPinSidebarWidth(150) == 180, "하한 미만은 180으로 clamp")
        #expect(PopoverWindow.clampPinSidebarWidth(300) == 300, "범위 내는 그대로 통과")
        #expect(PopoverWindow.clampPinSidebarWidth(500) == 400, "상한 초과는 400으로 clamp")
        // 경계값 정확성
        #expect(PopoverWindow.clampPinSidebarWidth(180) == 180)
        #expect(PopoverWindow.clampPinSidebarWidth(400) == 400)
    }

    // MARK: 저장값 복원 — nil → 기본(220) / 저장 → clamp

    @Test("resolveStoredPinSidebarWidth — 미설정 시 기본 220, 저장값은 clamp 적용")
    func restoreFallbackAndClamp() {
        // (a) UserDefaults 미설정 → 기본 220 (DesignTokens 기본값)
        #expect(PopoverWindow.resolveStoredPinSidebarWidth(stored: nil) == DesignTokens.WindowSize.pinSidebarWidth)
        #expect(PopoverWindow.resolveStoredPinSidebarWidth(stored: nil) == 220)
        // (b) 범위 내 저장값 → 그대로
        #expect(PopoverWindow.resolveStoredPinSidebarWidth(stored: 300) == 300)
        // (c) 상한 초과 저장값 → 400 clamp (손상/과거값 방어)
        #expect(PopoverWindow.resolveStoredPinSidebarWidth(stored: 999) == 400)
        // (d) 하한 미만 저장값 → 180 clamp
        #expect(PopoverWindow.resolveStoredPinSidebarWidth(stored: 50) == 180)
    }

    // MARK: origin 재계산 — 안쪽 엣지 popover 밀착 불변 (너비 성장 시)

    @Test("origin 불변 — .left 배치: 너비가 커져도 안쪽(오른쪽) 엣지 x는 popover 좌측에 고정, 바깥(왼쪽)으로 성장")
    func leftDirectionInnerEdgeInvariant() {
        let popover = CGRect(x: 500, y: 100, width: 380, height: 520)
        let gap: CGFloat = 8
        let originAt220 = ClipDetailDirection.left.originX(anchorFrame: popover, totalWidth: 220, gap: gap)
        let originAt350 = ClipDetailDirection.left.originX(anchorFrame: popover, totalWidth: 350, gap: gap)
        // 안쪽(오른쪽) 엣지 = originX + width — 너비 무관하게 popover.minX - gap 로 고정
        #expect(originAt220 + 220 == popover.minX - gap, "220일 때 안쪽 엣지가 popover 좌측 - gap")
        #expect(originAt350 + 350 == popover.minX - gap, "350일 때도 안쪽 엣지 동일 (밀착 유지)")
        // 바깥(왼쪽) 엣지는 너비만큼 왼쪽으로 성장 (originX 감소)
        #expect(originAt350 < originAt220, "너비 커지면 originX는 왼쪽으로 감소")
        #expect(originAt220 - originAt350 == 130, "성장분 = 350 - 220 = 130")
    }

    @Test("origin 불변 — .right 배치: 너비가 커져도 안쪽(왼쪽) 엣지 originX는 popover 우측에 고정")
    func rightDirectionInnerEdgeInvariant() {
        let popover = CGRect(x: 500, y: 100, width: 380, height: 520)
        let gap: CGFloat = 8
        let originAt220 = ClipDetailDirection.right.originX(anchorFrame: popover, totalWidth: 220, gap: gap)
        let originAt350 = ClipDetailDirection.right.originX(anchorFrame: popover, totalWidth: 350, gap: gap)
        // 안쪽(왼쪽) 엣지 = originX — 너비 무관하게 popover.maxX + gap 로 고정
        #expect(originAt220 == popover.maxX + gap, "220일 때 안쪽 엣지가 popover 우측 + gap")
        #expect(originAt350 == originAt220, "350일 때도 originX 동일 (밀착 유지, 오른쪽으로 성장)")
    }

    // MARK: 라이브 리사이즈 — 너비만 clamp, 높이 고정

    @Test("resolvePinSidebarResize — 너비는 clamp, 높이는 제안 무시하고 현재값 고정")
    func resizeWidthOnlyHeightFixed() {
        let currentHeight: CGFloat = 372
        // 범위 내 너비 통과 + 높이 불변
        let a = PopoverWindow.resolvePinSidebarResize(proposedWidth: 300, currentHeight: currentHeight)
        #expect(a.width == 300 && a.height == currentHeight, "범위 내 너비 통과, 높이 고정")
        // 상한 초과 너비 clamp + 높이 불변 (사용자가 코너로 세로도 끌어도 높이 거부)
        let b = PopoverWindow.resolvePinSidebarResize(proposedWidth: 999, currentHeight: currentHeight)
        #expect(b.width == 400 && b.height == currentHeight, "상한 clamp, 높이 고정")
        // 하한 미만 너비 clamp + 높이 불변
        let c = PopoverWindow.resolvePinSidebarResize(proposedWidth: 100, currentHeight: currentHeight)
        #expect(c.width == 180 && c.height == currentHeight, "하한 clamp, 높이 고정")
    }
}
