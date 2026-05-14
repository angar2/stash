// 방식 1 popover — 메뉴바 좌클릭 진입. PopoverPanel 헬퍼 사용 (NSPanel + NSVisualEffectView setup 통합)
import AppKit
import SwiftUI
import OSLog

@MainActor
final class Method1Window {
    private let panel: KeyablePanel
    private let visualEffectView: NSVisualEffectView
    private let viewModel: ClipsViewModel
    private let onOpenSettings: @MainActor () -> Void
    private lazy var outsideClickMonitor = OutsideClickMonitor { [weak self] in
        self?.hide()
    }
    private var currentAnchorOffsetX: CGFloat = DesignTokens.WindowSize.popoverWidth / 2

    init(
        viewModel: ClipsViewModel,
        onOpenSettings: @MainActor @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        let (p, ve) = PopoverPanel.make(
            width: DesignTokens.WindowSize.popoverWidth,
            height: 520
        )
        self.panel = p
        self.visualEffectView = ve
        rebuildHosting()
    }

    var isVisible: Bool { panel.isVisible }

    func show(below button: NSStatusBarButton) {
        currentAnchorOffsetX = PopoverPanel.positionBelow(panel: panel, button: button)
        rebuildHosting()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        outsideClickMonitor.install()
        Logger.ui.info("Method1Window shown — menu bar left click")
    }

    func hide() {
        outsideClickMonitor.remove()
        panel.orderOut(nil)
        Logger.ui.info("Method1Window hidden")
    }

    private func rebuildHosting() {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: .method1,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in self?.hide() },
            anchorOffsetX: currentAnchorOffsetX
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
