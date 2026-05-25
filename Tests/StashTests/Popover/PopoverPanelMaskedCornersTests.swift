// PopoverPanel.make() — 시스템 표준 NSWindow 패턴 회귀 차단 단위 테스트 (TASK-070 정합)
// 이전 정책 (TASK-038): VE.layer.cornerRadius + maskedCorners 박음 / 변경 (TASK-070): 시스템 NSWindow 자체 corner 박음 (titled + transparent titlebar)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverPanel 시스템 표준 NSWindow 패턴 (TASK-070)")
struct PopoverPanelMaskedCornersTests {
    /// TASK-070 — `make()` 가 시스템 표준 NSWindow 패턴 박는지 검증. `.titled + .fullSizeContentView + .nonactivatingPanel + .resizable` styleMask + titlebarAppearsTransparent=true + titleVisibility=.hidden + 3 button hidden. 시스템 자체가 4 모서리 둥글림 + 보더 + 그림자 박음.
    @Test("TASK-070 — make() 결과는 시스템 표준 NSWindow 패턴")
    func makeAppliesSystemStandardWindow() {
        let (panel, _) = PopoverPanel.make(width: 380, height: 480)

        #expect(panel.styleMask.contains(.titled), "styleMask 에 .titled 박혀야 시스템 자체 corner/보더/그림자 박힘")
        #expect(panel.styleMask.contains(.fullSizeContentView), "styleMask 에 .fullSizeContentView 박혀야 contentView 가 titlebar 영역까지 확장")
        #expect(panel.styleMask.contains(.nonactivatingPanel), "styleMask 에 .nonactivatingPanel 박혀야 외부 앱 frontmost 보존")
        #expect(panel.styleMask.contains(.resizable), "styleMask 에 .resizable 박혀야 시스템 표준 resize 가능")

        #expect(panel.titlebarAppearsTransparent == true, "titlebarAppearsTransparent=true 박혀야 titlebar 시각 분리감 제거")
        #expect(panel.titleVisibility == .hidden, "titleVisibility=.hidden 박혀야 title 텍스트 표시 X")

        #expect(panel.standardWindowButton(.closeButton)?.isHidden == true, "close 버튼 hidden")
        #expect(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true, "minimize 버튼 hidden")
        #expect(panel.standardWindowButton(.zoomButton)?.isHidden == true, "zoom 버튼 hidden")
    }

    /// TASK-071 — `make()` 가 isMovableByWindowBackground=true 박는지 검증. PopoverWindow.showInternal 의 *방식 1·2·3 mode 가드 제거* 정합의 기반 전제 — 모든 mode 가 본체 드래그 자유 이동 활성. PopoverWindow.swift 가 이 초기값을 덮어쓰면 안 됨.
    @Test("TASK-071 — make() 결과는 isMovableByWindowBackground=true (방식 1·2·3 본체 드래그 통일 인프라)")
    func makeAppliesMovableByWindowBackground() {
        let (panel, _) = PopoverPanel.make(width: 380, height: 480)
        #expect(panel.isMovableByWindowBackground == true,
                "PopoverPanel.make 가 isMovableByWindowBackground=true 박아야 PopoverWindow.showInternal 의 mode 가드 제거 후 방식 1·2·3 모두 본체 드래그 활성 보장")
    }

    /// TASK-075 — `makeBubble()` 가 borderless + transparent + hasShadow 패턴 박는지 검증. 상세 sub-window 의 bubble + arrow 시각 paradigm 정합. `make` 의 `.titled` 시스템 chrome 이 panel.frame 직사각형 외곽에 그려져 꼭지(arrow) 가 outline 안쪽에 갇히는 회귀 차단의 기반 전제.
    @Test("TASK-075 — makeBubble() 결과는 borderless + transparent + hasShadow (시스템 chrome 없음)")
    func makeBubbleReturnsBorderlessTransparentPanel() {
        let (panel, _) = PopoverPanel.makeBubble(width: 248, height: 200)

        #expect(panel.styleMask.contains(.borderless),
                "styleMask 에 .borderless 박혀야 시스템 chrome (corner/border/shadow) 박지 않음")
        #expect(panel.styleMask.contains(.titled) == false,
                "styleMask 에 .titled 박히면 시스템 chrome 직사각형 outline 박혀 꼭지가 안쪽에 갇힘 (root cause)")
        #expect(panel.styleMask.contains(.resizable) == false,
                "상세 sub-window 는 리사이즈 불가 — .resizable 박지 않음")
        #expect(panel.styleMask.contains(.nonactivatingPanel),
                "styleMask 에 .nonactivatingPanel 박혀야 외부 앱 frontmost 보존 (make 와 공통)")
        #expect(panel.styleMask.contains(.fullSizeContentView),
                "styleMask 에 .fullSizeContentView 박혀야 contentView 가 panel 전체 영역 사용 (make 와 공통)")

        #expect(panel.isOpaque == false,
                "isOpaque=false 박혀야 transparent panel — mask 영역 밖 픽셀 투명")
        #expect(panel.backgroundColor == NSColor.clear,
                "backgroundColor=.clear 박혀야 시스템이 panel 배경 채우지 않음 — mask 가 단독으로 bubble + arrow shape 결정")
        #expect(panel.hasShadow == true,
                "hasShadow=true 박혀야 alpha mask (bubble + arrow) 따라 그림자 자연 박힘")
    }

    /// TASK-075 — `makeBubble()` 반환 VE 가 cornerRadius / border 박지 않는지 검증. mask 가 본문 + 꼭지 shape 단독 책임 정합. VE.layer 가 cornerRadius/border 박으면 mask 와 중복 + 꼭지 확장 영역에서 시각 충돌 가능.
    @Test("TASK-075 — makeBubble() 반환 VE 는 cornerRadius / border 박지 않음 (mask 단독 책임)")
    func makeBubbleVisualEffectViewHasNoCornerRadiusOrBorder() {
        let (_, ve) = PopoverPanel.makeBubble(width: 248, height: 200)

        #expect((ve.layer?.cornerRadius ?? 0) == 0,
                "VE.layer.cornerRadius 박지 않아야 mask 가 본문 둥근 사각형 + 꼭지 삼각형 shape 단독 책임")
        #expect((ve.layer?.borderWidth ?? 0) == 0,
                "VE.layer.borderWidth 박지 않아야 mask 영역 밖 border 그려지지 않음 — 꼭지 확장 영역 시각 충돌 차단")
        #expect(ve.material == .popover, "material .popover (make 와 공통)")
        #expect(ve.blendingMode == .behindWindow, "blendingMode .behindWindow (make 와 공통)")
        #expect(ve.state == .active, "state .active (make 와 공통)")
        #expect(ve.isEmphasized == true, "isEmphasized=true (make 와 공통)")
    }

    /// TASK-075 — `make` / `makeBubble` 공통 동작 정책 동등 검증. popover 동반 시각 컴패니언으로 동일 동작 정책 (level / hidesOnDeactivate / collectionBehavior / becomesKeyOnlyIfNeeded / acceptsMouseMovedEvents) 필요. 두 헬퍼가 *시각 paradigm* 만 분기 (시스템 chrome 유무) — 그 외 panel 동작은 일치.
    @Test("TASK-075 — make / makeBubble 공통 panel 동작 정책 동등")
    func makeBubbleAndMakeShareCommonPolicies() {
        let (p1, _) = PopoverPanel.make(width: 380, height: 480)
        let (p2, _) = PopoverPanel.makeBubble(width: 248, height: 200)

        // 공통 styleMask 비트 — .nonactivatingPanel + .fullSizeContentView 두 panel 모두 박힘.
        #expect(p1.styleMask.contains(.nonactivatingPanel) && p2.styleMask.contains(.nonactivatingPanel),
                ".nonactivatingPanel 공통")
        #expect(p1.styleMask.contains(.fullSizeContentView) && p2.styleMask.contains(.fullSizeContentView),
                ".fullSizeContentView 공통")

        // panel 동작 정책 공통.
        let expectedLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        #expect(p1.level == expectedLevel && p2.level == expectedLevel,
                "level Dock+1 공통 (Dock 자동 숨김 hover 등장 시 popover 가 가려지지 않음)")
        #expect(p1.hasShadow == true && p2.hasShadow == true,
                "hasShadow=true 공통")
        #expect(p1.hidesOnDeactivate == false && p2.hidesOnDeactivate == false,
                "hidesOnDeactivate=false 공통")
        #expect(p1.becomesKeyOnlyIfNeeded == true && p2.becomesKeyOnlyIfNeeded == true,
                "becomesKeyOnlyIfNeeded=true 공통 (TASK-058 fix-2)")
        #expect(p1.acceptsMouseMovedEvents == true && p2.acceptsMouseMovedEvents == true,
                "acceptsMouseMovedEvents=true 공통 (TASK-060)")
        #expect(p1.collectionBehavior.contains(.fullScreenAuxiliary) && p2.collectionBehavior.contains(.fullScreenAuxiliary),
                "collectionBehavior .fullScreenAuxiliary 공통")
        #expect(p1.collectionBehavior.contains(.transient) && p2.collectionBehavior.contains(.transient),
                "collectionBehavior .transient 공통")
        #expect(p1.collectionBehavior.contains(.canJoinAllSpaces) && p2.collectionBehavior.contains(.canJoinAllSpaces),
                "collectionBehavior .canJoinAllSpaces 공통")
    }
}
