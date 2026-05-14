// 방식 2 popover — ⌘ hold 진입 / ⌘ keyUp 닫힘. 미니멀 (검색·환경설정·삭제 X). PopoverPanel 헬퍼 사용
import AppKit
import SwiftUI
import OSLog

@MainActor
final class Method2Window {
    private let panel: KeyablePanel
    private let visualEffectView: NSVisualEffectView
    private let viewModel: ClipsViewModel

    init(viewModel: ClipsViewModel) {
        self.viewModel = viewModel
        let (p, ve) = PopoverPanel.make(
            width: DesignTokens.WindowSize.popoverWidth,
            height: 320
        )
        self.panel = p
        self.visualEffectView = ve
        rebuildHosting()
    }

    func show() {
        PopoverPanel.positionAtBottomRight(panel)
        panel.orderFrontRegardless()
        Logger.ui.info("Method2Window shown — ⌘ hold")
    }

    func hide() {
        panel.orderOut(nil)
        Logger.ui.info("Method2Window hidden — ⌘ keyUp")
    }

    private func rebuildHosting() {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: .method2,
            onOpenSettings: {},
            onDismiss: {},
            anchorOffsetX: nil
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
