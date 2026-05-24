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
}
