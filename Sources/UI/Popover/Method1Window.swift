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
    /// popover 안 mouseDown 잡아 검색바 외부 click 시 first responder reset (D-3 outside click deactivate).
    private var localClickMonitor: Any?

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
        // FrontmostAppTracker는 항상 *직전 앱*을 보관 — show 시점에 stash가 frontmost가 되어도 이전 사용자 앱은 보존됨.
        currentAnchorOffsetX = PopoverPanel.positionBelow(panel: panel, button: button)
        viewModel.resetForOpen()  // popover 열 때마다 검색부 비활성 + 첫 클립 선택 커서
        rebuildHosting()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        // panel 자체를 first responder로 — NSTextField가 자동 first responder 가져가는 것 차단.
        panel.makeFirstResponder(panel)
        outsideClickMonitor.install()
        installLocalClickMonitor()
        Logger.ui.info("Method1Window shown — menu bar left click (tracker prev: \(FrontmostAppTracker.shared.previousApp?.bundleIdentifier ?? "nil", privacy: .public))")
    }

    func hide() {
        outsideClickMonitor.remove()
        removeLocalClickMonitor()
        panel.orderOut(nil)
        Logger.ui.info("Method1Window hidden")
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

    /// 클립 paste 흐름 — PopoverPanel.performPasteFlow 헬퍼로 위임 (Method1/2/3 공통 흐름).
    private func handleClipPaste(at idx: Int) async {
        await PopoverPanel.performPasteFlow(
            viewModel: viewModel,
            idx: idx,
            sourceLabel: "Method1Window",
            hide: { [weak self] in self?.hide() }
        )
    }

    private func rebuildHosting() {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: .method1,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            },
            anchorOffsetX: currentAnchorOffsetX
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
