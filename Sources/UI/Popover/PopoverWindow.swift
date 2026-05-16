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

    /// Pin 사이드바 별도 floating panel — popover 좌측에 분리 노출 (TASK-019 fix). 단일 인스턴스 재사용.
    private let pinSidebarPanel: KeyablePanel
    private let pinSidebarVisualEffect: NSVisualEffectView

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
        // TASK-019 — Pin 사이드바 별도 NSPanel. popover 좌측 floating. height 는 PinSidebarView 의 자연 사이즈를 따르되 popover height 상한.
        let (sp, sve) = PopoverPanel.make(
            width: DesignTokens.WindowSize.pinSidebarWidth,
            height: DesignTokens.WindowSize.popoverHeight
        )
        self.pinSidebarPanel = sp
        self.pinSidebarVisualEffect = sve

        // ClipsViewModel.pinSidebarOpen 변경 콜백 등록 — true → show / false → hide.
        viewModel.onPinSidebarOpenChange = { [weak self] isOpen in
            guard let self else { return }
            if isOpen {
                self.showPinSidebar()
            } else {
                self.hidePinSidebar()
            }
        }
        // pinnedClips count 변화 콜백 — 사이드바 열려있으면 panel size 재조정.
        viewModel.onPinnedClipsChange = { [weak self] in
            guard let self, self.viewModel.pinSidebarOpen else { return }
            self.resizePinSidebarPanel()
        }
    }

    /// TASK-019 fix 2차 — pinnedClips count 변화 시 panel size 재조정 (bottom-aligned 유지).
    private func resizePinSidebarPanel() {
        guard pinSidebarPanel.isVisible else { return }
        let popoverFrame = panel.frame
        let gap = DesignTokens.Spacing.pinSidebarGap
        let sidebarWidth = DesignTokens.WindowSize.pinSidebarWidth
        let sidebarHeight = computePinSidebarHeight()
        let originX = popoverFrame.origin.x - gap - sidebarWidth
        let originY = popoverFrame.origin.y  // bottom-aligned
        pinSidebarPanel.setFrame(
            NSRect(x: originX, y: originY, width: sidebarWidth, height: sidebarHeight),
            display: true,
            animate: false
        )
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
        // Pin 사이드바도 동반 닫음 (popover 닫히면 사이드바 단독 노출 의미 없음).
        if viewModel.pinSidebarOpen {
            viewModel.collapsePinSidebar()  // didSet → hidePinSidebar()
        } else {
            hidePinSidebar()  // 안전망 — pinSidebarOpen=false 인데 패널만 떠 있는 비정상 상태 정리.
        }
        panel.orderOut(nil)
        Logger.ui.info("PopoverWindow hidden — mode=\(String(describing: mode), privacy: .public)")
        currentMode = nil
    }

    // MARK: - Pin 사이드바 별도 패널 (TASK-019 fix)

    private func showPinSidebar() {
        // popover 좌측 외부 — popover.origin.x - gap - sidebar.width. y는 popover.origin.y (bottom-aligned).
        guard panel.isVisible, let mode = currentMode else {
            Logger.ui.warning("showPinSidebar called while popover hidden — skip")
            return
        }
        // hosting rebuild — 매 show마다 fresh SwiftUI tree (pinnedClips 변화 반영). mode + handleClipPaste 전달.
        _ = PopoverPanel.mount(
            PinSidebarView(
                viewModel: viewModel,
                mode: mode,
                handleClipPaste: { [weak self] idx in
                    await self?.handleClipPaste(at: idx)
                }
            ),
            in: pinSidebarVisualEffect
        )

        let popoverFrame = panel.frame
        let gap = DesignTokens.Spacing.pinSidebarGap
        let sidebarWidth = DesignTokens.WindowSize.pinSidebarWidth
        let sidebarHeight = computePinSidebarHeight()
        let originX = popoverFrame.origin.x - gap - sidebarWidth
        // bottom-aligned — popover 바닥과 사이드바 바닥 일치.
        let originY = popoverFrame.origin.y
        // TASK-019 fix 3차 — display:true + animate:false 박아 panel size 즉시 redraw (B6 — 첫 show 옛 size 잔존 차단).
        pinSidebarPanel.setFrame(
            NSRect(x: originX, y: originY, width: sidebarWidth, height: sidebarHeight),
            display: true,
            animate: false
        )
        pinSidebarPanel.orderFrontRegardless()
        Logger.ui.info("Pin sidebar panel shown — origin=(\(originX, privacy: .public),\(originY, privacy: .public)) h=\(sidebarHeight, privacy: .public)")
    }

    /// TASK-019 — Pin 사이드바 동적 height 계산. pinnedClips count 기반 + 본체 popoverHeight 미만 상한.
    /// 모든 상수는 `DesignTokens.Spacing` 으로 분리 (`pinSidebarHeaderHeight` / `pinSidebarHeightSafety` / `pinSidebarHeightBottomMargin`).
    /// ClipRowView 의 실제 single-line 행 height = `rowMinHeight + rowGap`. multiline 시 ScrollView 내부 스크롤이 흡수.
    private func computePinSidebarHeight() -> CGFloat {
        let itemH = DesignTokens.Spacing.rowMinHeight + DesignTokens.Spacing.rowGap
        let outerPad = DesignTokens.Spacing.pinSidebarPadding * 2 + DesignTokens.Spacing.pinSidebarHeightSafety
        let count = max(1, viewModel.pinnedClips.count)
        let contentH = DesignTokens.Spacing.pinSidebarHeaderHeight + CGFloat(count) * itemH + outerPad
        let upperBound = DesignTokens.WindowSize.popoverHeight - DesignTokens.Spacing.pinSidebarHeightBottomMargin
        return min(contentH, upperBound)
    }

    private func hidePinSidebar() {
        if pinSidebarPanel.isVisible {
            pinSidebarPanel.orderOut(nil)
            Logger.ui.info("Pin sidebar panel hidden")
        }
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

        // TASK-020 — NSApp.activate 호출 제거 (nonactivatingPanel 본질 보존). stash app이 active되지 않으므로 외부 앱이 frontmost 유지 + first responder 보존 + cursor 깜빡임 유지. paste 시점에 CGEvent ⌘V가 외부 앱의 마지막 cursor 위치에 정확히 도달.
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

        Logger.ui.info("PopoverWindow shown — mode=\(String(describing: mode), privacy: .public)")
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
