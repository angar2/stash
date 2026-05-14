// 방식 3 popover — ⌘ double-tap 진입 / ESC·외부 클릭 닫힘. 방식 1과 동일 콘텐츠. PopoverPanel 헬퍼 사용
import AppKit
import SwiftUI
import OSLog

@MainActor
final class Method3Window {
    private let panel: KeyablePanel
    private let visualEffectView: NSVisualEffectView
    private let viewModel: ClipsViewModel
    private let onOpenSettings: @MainActor () -> Void
    private lazy var outsideClickMonitor = OutsideClickMonitor { [weak self] in
        self?.hide()
    }

    init(
        viewModel: ClipsViewModel,
        onOpenSettings: @MainActor @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        let (p, ve) = PopoverPanel.make(
            width: DesignTokens.WindowSize.popoverWidth,
            height: 480
        )
        self.panel = p
        self.visualEffectView = ve
        rebuildHosting()
    }

    func show() {
        PopoverPanel.positionAtBottomRight(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        outsideClickMonitor.install()
        Logger.ui.info("Method3Window shown — ⌘ double-tap")
    }

    func hide() {
        outsideClickMonitor.remove()
        panel.orderOut(nil)
        Logger.ui.info("Method3Window hidden")
    }

    private func rebuildHosting() {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: .method3,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in self?.hide() },
            anchorOffsetX: nil
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
