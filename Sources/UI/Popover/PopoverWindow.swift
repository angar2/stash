// 1·2·3 호출 방식 통합 popover Window — `mode` 분기로 위치/activate/monitor/resetForOpen 차이 처리 (TASK-018)
// 인스턴스 단일화로 모드 간 중복 노출 *물리적* 차단. 기존 Method1/2/3Window 폐기.
import AppKit
import SwiftUI
import OSLog

@MainActor
final class PopoverWindow {
    private let panel: KeyablePanel
    private let visualEffectView: NSVisualEffectView
    private let viewModel: ClipsViewModel
    private let onOpenSettings: @MainActor () -> Void

    /// 현재 표시 중인 mode. nil = hidden. mode 전환 시 hide → showInternal에서 갱신.
    private var currentMode: PopoverInvocationMode?
    /// 방식 1 arrow tail 위치 (popover 좌표계 안 button center x).
    private var currentAnchorOffsetX: CGFloat = DesignTokens.WindowSize.popoverWidth / 2

    private lazy var outsideClickMonitor = OutsideClickMonitor { [weak self] in
        self?.hide()
    }
    /// popover 안 mouseDown 잡아 검색바 외부 click 시 first responder reset (TASK-016 D-3). 방식 1·3만 설치.
    private var localClickMonitor: Any?
    /// ESC 키 monitor — 검색 활성 상태에서 ESC를 NSTextView consume 전 가로채 비활성화 (TASK-017 fix-3 v4). 방식 1·3만 설치.
    private var escapeKeyMonitor: Any?

    init(
        viewModel: ClipsViewModel,
        onOpenSettings: @MainActor @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        let (p, ve) = PopoverPanel.make(
            width: DesignTokens.WindowSize.popoverWidth,
            height: DesignTokens.WindowSize.popoverHeight
        )
        self.panel = p
        self.visualEffectView = ve
    }

    var isVisible: Bool { panel.isVisible }

    /// 방식 1 — 메뉴바 button 아래 anchor.
    func show(below button: NSStatusBarButton) {
        showInternal(mode: .method1, below: button)
    }

    /// 방식 2·3 — 활성 화면 우하단.
    /// - Precondition: `mode != .method1`. 방식 1은 `show(below:)` 사용.
    func show(mode: PopoverInvocationMode) {
        precondition(mode != .method1, "방식 1은 show(below:) 사용. button anchor 필수.")
        showInternal(mode: mode, below: nil)
    }

    func hide() {
        guard let mode = currentMode else {
            // 이미 hidden 상태에서 hide() 호출 — 멱등 안전 (⌘ keyUp 등 외부 트리거 멱등).
            return
        }
        // 방식 1·3 — monitor 정리.
        if mode != .method3 {
            outsideClickMonitor.remove()
            removeLocalClickMonitor()
            removeEscapeKeyMonitor()
        }
        panel.orderOut(nil)
        Logger.ui.info("PopoverWindow hidden — mode=\(String(describing: mode), privacy: .public)")
        currentMode = nil
    }

    // MARK: - 내부 표시 흐름

    private func showInternal(mode: PopoverInvocationMode, below button: NSStatusBarButton?) {
        // 다른 mode가 이미 떠 있으면 먼저 hide (모드 간 전환 — "마지막 호출 우선" 룰).
        if currentMode != nil {
            hide()
        }

        currentMode = mode

        // 위치 — 방식 1만 메뉴바 anchor / 방식 2·3은 우하단.
        if let button {
            currentAnchorOffsetX = PopoverPanel.positionBelow(panel: panel, button: button)
        } else {
            PopoverPanel.positionAtBottomRight(panel)
        }

        // resetForOpen — 방식 1·3만 (방식 2는 ⌘ hold 중 매 재진입마다 reset하면 검색 상태 등 끊김 — 기존 동작 보존).
        if mode != .method3 {
            viewModel.resetForOpen()
        }

        // hosting rebuild — 매 show마다 새 SwiftUI tree 박음 (mode 인자 변경 반영).
        rebuildHosting(mode: mode)

        // activate — 방식 1·3만. 방식 2는 ⌘ hold 중 frontmost 보존 위해 skip (paste 시 직전 앱 복원).
        if mode != .method3 {
            NSApp.activate(ignoringOtherApps: true)
        }

        panel.orderFrontRegardless()
        panel.makeKey()

        // first responder — 방식 1·3만. panel 자체를 first responder로 박아 NSTextField 자동 first responder 차단 (TASK-016 D-3).
        // 방식 2는 검색바 노출하되 입력 비활성 (Phase 2)이라 first responder 박지 않음 — NSTextField는 어차피 disabled 상태.
        if mode != .method3 {
            panel.makeFirstResponder(panel)
        }

        // monitor 설치 — 방식 1·3만. 방식 2는 ⌘ keyUp으로만 닫힘.
        if mode != .method3 {
            outsideClickMonitor.install()
            installLocalClickMonitor()
            installEscapeKeyMonitor()
        }

        // 키 이벤트 핸들러 — 모든 mode 설치.
        installKeyDownHandler(mode: mode)

        Logger.ui.info("PopoverWindow shown — mode=\(String(describing: mode), privacy: .public) (tracker prev: \(FrontmostAppTracker.shared.previousApp?.bundleIdentifier ?? "nil", privacy: .public))")
    }

    private func installKeyDownHandler(mode: PopoverInvocationMode) {
        PopoverPanel.installKeyDownHandler(
            panel: panel,
            viewModel: viewModel,
            mode: mode,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            }
        )
    }

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

    private func installEscapeKeyMonitor() {
        removeEscapeKeyMonitor()
        escapeKeyMonitor = PopoverPanel.installSearchEscapeMonitor(panel: panel, viewModel: viewModel)
    }

    private func removeEscapeKeyMonitor() {
        if let m = escapeKeyMonitor {
            NSEvent.removeMonitor(m)
            escapeKeyMonitor = nil
        }
    }

    /// 클립 paste 흐름 — PopoverPanel.performPasteFlow 헬퍼로 위임.
    private func handleClipPaste(at idx: Int) async {
        let label = currentMode.map { "PopoverWindow(\(String(describing: $0)))" } ?? "PopoverWindow"
        await PopoverPanel.performPasteFlow(
            viewModel: viewModel,
            idx: idx,
            sourceLabel: label,
            hide: { [weak self] in self?.hide() }
        )
    }

    private func rebuildHosting(mode: PopoverInvocationMode) {
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: mode,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            },
            anchorOffsetX: mode == .method1 ? currentAnchorOffsetX : nil
        )
        _ = PopoverPanel.mount(view, in: visualEffectView)
    }
}
