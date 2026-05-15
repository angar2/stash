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
        // key window 활성화 — SwiftUI .onKeyPress가 키 이벤트 받으려면 panel이 key window여야 함 (TASK-017 Phase 3).
        panel.makeKey()
        // KeyablePanel.keyDownHandler 셋업 — AppKit 단 키 직접 처리 (TASK-017 fix-2).
        PopoverPanel.installKeyDownHandler(
            panel: panel,
            viewModel: viewModel,
            mode: .method2,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            }
        )
        Logger.ui.info("Method2Window shown — ⌘ hold (tracker prev: \(FrontmostAppTracker.shared.previousApp?.bundleIdentifier ?? "nil", privacy: .public))")
    }

    func hide() {
        panel.orderOut(nil)
        Logger.ui.info("Method2Window hidden — ⌘ keyUp")
    }

    /// 클립 paste 흐름 — PopoverPanel.performPasteFlow 헬퍼로 위임. (방식 2는 hold release 시 별도 hide 호출 — hide() 멱등 안전).
    private func handleClipPaste(at idx: Int) async {
        await PopoverPanel.performPasteFlow(
            viewModel: viewModel,
            idx: idx,
            sourceLabel: "Method2Window",
            hide: { [weak self] in self?.hide() }
        )
    }

    private func rebuildHosting() {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: .method2,
            onOpenSettings: {},
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            },
            anchorOffsetX: nil
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
