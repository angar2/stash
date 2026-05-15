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
    private var localClickMonitor: Any?

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
        viewModel.resetForOpen()  // popover 열 때마다 검색부 비활성 + 첫 클립 선택 커서
        PopoverPanel.positionAtBottomRight(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        // panel 자체를 first responder로 — NSTextField 자동 first responder 차단.
        panel.makeFirstResponder(panel)
        outsideClickMonitor.install()
        installLocalClickMonitor()
        Logger.ui.info("Method3Window shown — ⌘ double-tap (tracker prev: \(FrontmostAppTracker.shared.previousApp?.bundleIdentifier ?? "nil", privacy: .public))")
    }

    func hide() {
        outsideClickMonitor.remove()
        removeLocalClickMonitor()
        panel.orderOut(nil)
        Logger.ui.info("Method3Window hidden")
    }

    /// PopoverPanel.installOutsideTextFieldClickMonitor 헬퍼 위임 (Method1/3 공통).
    private func installLocalClickMonitor() {
        removeLocalClickMonitor()
        localClickMonitor = PopoverPanel.installOutsideTextFieldClickMonitor(panel: panel)
    }

    private func removeLocalClickMonitor() {
        if let m = localClickMonitor {
            NSEvent.removeMonitor(m)
            localClickMonitor = nil
        }
    }

    /// 클립 paste 흐름 — PopoverPanel.performPasteFlow 헬퍼로 위임.
    private func handleClipPaste(at idx: Int) async {
        await PopoverPanel.performPasteFlow(
            viewModel: viewModel,
            idx: idx,
            sourceLabel: "Method3Window",
            hide: { [weak self] in self?.hide() }
        )
    }

    private func rebuildHosting() {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: .method3,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            },
            anchorOffsetX: nil
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
