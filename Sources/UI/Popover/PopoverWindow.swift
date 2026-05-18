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
    /// TASK-025 — popover 안 mouseDown 잡아 검색바 외부 click 시 NSTextField first responder *복원* (이전 TASK-016 의 *해제* 방향 반대). 방식 1·2만 설치.
    private var localClickMonitor: Any?
    /// TASK-025 — popover 키 라우팅 monitor (NSTextView consume 전 PopoverHotkey 매칭 + Tab consume). 이전 ESC monitor 의 모든 키 라우팅으로 확장. 방식 1·2만 설치.
    private var popoverKeyMonitor: Any?

    /// Pin 사이드바 별도 floating panel — popover 좌측에 분리 노출 (TASK-019 fix). 단일 인스턴스 재사용.
    private let pinSidebarPanel: KeyablePanel
    private let pinSidebarVisualEffect: NSVisualEffectView

    /// 클립 상세 sub-window 별도 floating panel — popover 또는 PinSidebar 좌측에 다중파일 클립 detail 표시 (TASK-027). 단일 인스턴스 재사용.
    private let detailPanel: KeyablePanel
    private let detailVisualEffect: NSVisualEffectView
    /// 마지막 표시 detail 요청 — PinSidebar 사이즈 변경 시 anchor 재계산용 (TASK-027 Phase 5).
    private var lastShownDetailRequest: ClipDetailRequest?

    /// detail panel 총 width — 본문(clipDetailWidth) + 꼭지(clipDetailArrowWidth). NSPanel make / setFrame / originX 계산 모두 본 값 사용 (TASK-027 refactor — 3 곳 중복 계산 통합).
    static var clipDetailTotalWidth: CGFloat {
        DesignTokens.WindowSize.clipDetailWidth + DesignTokens.Spacing.clipDetailArrowWidth
    }

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

        // TASK-027 — 클립 상세 sub-window 별도 NSPanel. popover (또는 PinSidebar) 좌측 floating. height 는 Provider.preferredHeight 동적 계산.
        // width = clipDetailWidth (본문) + clipDetailArrowWidth (꼭지 외부 튀어나옴 영역). NSVisualEffectView.maskImage 가 panel 자체를 말풍선 모양으로 잘라냄 (TASK-027 fix).
        let (dp, dve) = PopoverPanel.make(
            width: Self.clipDetailTotalWidth,
            height: DesignTokens.WindowSize.clipDetailMaxHeight
        )
        self.detailPanel = dp
        self.detailVisualEffect = dve

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
        // TASK-027 — ClipsViewModel.onShowClipDetailChange 콜백 등록. non-nil → showClipDetailPanel / nil → hide.
        viewModel.onShowClipDetailChange = { [weak self] request in
            guard let self else { return }
            if let request {
                self.showClipDetailPanel(request)
            } else {
                self.hideClipDetailPanel()
            }
        }
    }

    /// TASK-019 fix 2차 — pinnedClips count 변화 시 panel size 재조정 (bottom-aligned 유지).
    /// TASK-027 — Pin 사이드바 사이즈 변동 후 detail panel 활성이면 anchor 재계산 (200ms debounce 없이 즉시).
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
        // TASK-027 — detail panel 활성이고 zone == .pin 이면 PinSidebar 새 anchor 로 setFrame 재계산.
        if let last = lastShownDetailRequest, last.zone == .pin, detailPanel.isVisible {
            showClipDetailPanel(last)
        }
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
        // 방식 1·2 — monitor 정리 (method3 보류는 monitor 미설치).
        if mode != .method3 {
            outsideClickMonitor.remove()
            removeLocalClickMonitor()
            removePopoverKeyMonitor()
        }
        // TASK-027 — Detail sub-window 동반 닫음.
        hideClipDetailPanel()
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

    // MARK: - 클립 상세 sub-window (TASK-027)

    /// `ClipsViewModel.onShowClipDetailChange` 콜백 진입점 (non-nil 케이스). zone 분기 anchor + 화면 좌표 변환 + 클램프 + 꼭지 Y 보정.
    /// FEATURES §3-8 *위치 + 좌표 변환* 정합.
    private func showClipDetailPanel(_ request: ClipDetailRequest) {
        // method3 (⌘ hold) 보류 가드 — detail sub-window 진입 X.
        guard let mode = currentMode, mode != .method3 else {
            hideClipDetailPanel()
            return
        }
        guard panel.isVisible else {
            hideClipDetailPanel()
            return
        }
        // anchor 결정 — zone == .pin && pinSidebar 가시 시 pinSidebar 좌측, 그 외 popover 좌측.
        let anchorFrame: NSRect
        if request.zone == .pin && pinSidebarPanel.isVisible {
            anchorFrame = pinSidebarPanel.frame
        } else {
            anchorFrame = panel.frame
        }
        // detail panel height — Provider.preferredHeight 우선, fallback clipDetailMaxHeight.
        let provider = ClipDetailRegistry.provider(for: request.clip)
        let detailH = provider?.preferredHeight(for: request.clip) ?? DesignTokens.WindowSize.clipDetailMaxHeight
        // TASK-027 fix — panel 총 width = 본문(clipDetailWidth) + 꼭지(clipDetailArrowWidth). maskImage 로 panel 자체를 말풍선 모양으로 잘라냄.
        let totalW = Self.clipDetailTotalWidth
        let gap = DesignTokens.Spacing.clipDetailGap
        let safe = DesignTokens.Spacing.clipDetailEdgeSafety

        // originX 계산 + 화면 좌측 클램프 — totalW (본문+꼭지) 사용.
        var originX = anchorFrame.origin.x - gap - totalW
        let screenVisible = panel.screen?.visibleFrame ?? .zero
        originX = max(screenVisible.minX + safe, originX)

        // SwiftUI top-down ↔ NSPanel bottom-up 좌표 변환:
        // 행 center Y (SwiftUI, popoverBody 안 좌표계, top-down) = rowFrameInPopover.midY
        // 행 center Y (screen, bottom-up) = anchorFrame.origin.y + (anchorFrame.height - rowCenterY_SwiftUI)
        let rowCenterY_SwiftUI = request.rowFrameInPopover.midY
        let rowCenterY_screen = anchorFrame.origin.y + (anchorFrame.height - rowCenterY_SwiftUI)

        // detail panel originY (screen, bottom-up) — 꼭지가 행 center 가리키도록 기본은 panel 중앙에 꼭지.
        // detail panel 내부 arrowOffsetY (SwiftUI, top-down) 기본값 = detailH / 2 → detail.originY = rowCenterY_screen - detailH/2.
        var arrowOffsetY = detailH / 2
        var originY = rowCenterY_screen - (detailH - arrowOffsetY)

        // 화면 상/하단 클램프 — 클램프 발생 시 arrowOffsetY 보정으로 꼭지가 행 center 유지.
        let minY = screenVisible.minY + safe
        let maxY = screenVisible.maxY - detailH - safe
        if originY < minY {
            originY = minY
            arrowOffsetY = detailH - (rowCenterY_screen - originY)
        } else if originY > maxY {
            originY = maxY
            arrowOffsetY = detailH - (rowCenterY_screen - originY)
        }
        // arrowOffsetY 범위 [arrowH/2, detailH - arrowH/2] 가드.
        let arrowH = DesignTokens.Spacing.clipDetailArrowHeight
        arrowOffsetY = max(arrowH / 2, min(detailH - arrowH / 2, arrowOffsetY))

        // hosting rebuild — 매 show 마다 fresh SwiftUI tree (clip 변화 반영).
        _ = PopoverPanel.mount(
            ClipDetailPanelView(
                clip: request.clip,
                onFileTap: { [weak self] url in
                    self?.handleFileTap(url)
                }
            ),
            in: detailVisualEffect
        )
        detailPanel.setFrame(
            NSRect(x: originX, y: originY, width: totalW, height: detailH),
            display: true,
            animate: false
        )
        // TASK-027 fix — NSVisualEffectView.maskImage 박아 panel 자체를 말풍선 모양으로 잘라냄 (좌측 본문 직사각형 + 우측 꼭지 삼각형).
        detailVisualEffect.maskImage = makeBubbleMaskImage(detailH: detailH, arrowOffsetY: arrowOffsetY)
        detailPanel.orderFrontRegardless()
        lastShownDetailRequest = request
        Logger.ui.info("ClipDetailPanel shown — clipId=\(request.clip.id.uuidString, privacy: .public) zone=\(String(describing: request.zone), privacy: .public) origin=(\(originX, privacy: .public),\(originY, privacy: .public)) totalW=\(totalW, privacy: .public) h=\(detailH, privacy: .public) arrowY=\(arrowOffsetY, privacy: .public)")
    }

    /// TASK-027 fix — 말풍선 mask 이미지. 좌측 본문 직사각형 (rounded) + 우측 꼭지 삼각형. NSVisualEffectView.maskImage 로 박아 panel 자체가 말풍선 모양으로 잘림.
    /// `arrowOffsetY` 는 SwiftUI top-down 좌표 (panel top 기준 Y). NSImage flipped:false 는 bottom-up 좌표라 변환.
    private func makeBubbleMaskImage(detailH: CGFloat, arrowOffsetY: CGFloat) -> NSImage {
        let contentW = DesignTokens.WindowSize.clipDetailWidth
        let arrowW = DesignTokens.Spacing.clipDetailArrowWidth
        let arrowH = DesignTokens.Spacing.clipDetailArrowHeight
        let totalW = Self.clipDetailTotalWidth
        let cornerR = DesignTokens.Radius.popoverOuter
        let size = NSSize(width: totalW, height: detailH)

        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            // 좌측 본문 직사각형 (rounded corner).
            let bodyRect = NSRect(x: 0, y: 0, width: contentW, height: detailH)
            path.append(NSBezierPath(roundedRect: bodyRect, xRadius: cornerR, yRadius: cornerR))

            // 꼭지 삼각형 — arrowOffsetY 는 SwiftUI top-down. NSImage bottom-up 으로 변환.
            let arrowY_bottomUp = detailH - arrowOffsetY
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: contentW, y: arrowY_bottomUp - arrowH / 2))
            arrow.line(to: NSPoint(x: contentW + arrowW, y: arrowY_bottomUp))
            arrow.line(to: NSPoint(x: contentW, y: arrowY_bottomUp + arrowH / 2))
            arrow.close()
            path.append(arrow)

            NSColor.black.setFill()
            path.fill()
            return true
        }
        // maskImage 는 capInsets 가 stretching 영역 결정. 기본값 (.zero) 은 stretch X — panel size 변동 시 mask redraw 필요.
        image.capInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        image.resizingMode = .stretch
        return image
    }

    private func hideClipDetailPanel() {
        lastShownDetailRequest = nil
        if detailPanel.isVisible {
            detailPanel.orderOut(nil)
            Logger.ui.info("ClipDetailPanel hidden")
        }
    }

    /// 파일 행 클릭 → Finder reveal + popover dismiss. detailPanel 도 동반 hide (PopoverWindow.hide 안에서 처리).
    private func handleFileTap(_ url: URL) {
        Logger.ui.info("ClipDetailPanel handleFileTap → \(url.path, privacy: .public)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
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

        // resetForOpen — 방식 1·2만 (method3 보류는 ⌘ hold 중 매 재진입마다 reset하면 검색 상태 등 끊김 — 기존 동작 보존).
        if mode != .method3 {
            viewModel.resetForOpen()
        }

        // hosting rebuild — 매 show마다 새 SwiftUI tree 박음 (mode 인자 변경 반영).
        rebuildHosting(mode: mode)

        // TASK-020 — NSApp.activate 호출 제거 (nonactivatingPanel 본질 보존). stash app이 active되지 않으므로 외부 앱이 frontmost 유지 + first responder 보존 + cursor 깜빡임 유지. paste 시점에 CGEvent ⌘V가 외부 앱의 마지막 cursor 위치에 정확히 도달.
        panel.orderFrontRegardless()
        panel.makeKey()

        // first responder — 방식 1·2만. TASK-025 — NSTextField always-active 정책. find 실패 시 panel 자체로 fallback (안전망).
        // method3 (보류) 은 검색바 isEnabled=false 라 first responder 진입 못 함 — 기존대로 panel 자체 first responder.
        if mode != .method3 {
            if let textField = PopoverPanel.findFirstTextField(in: panel.contentView) {
                panel.makeFirstResponder(textField)
            } else {
                Logger.ui.warning("findFirstTextField returned nil — fallback to panel first responder (TASK-025)")
                panel.makeFirstResponder(panel)
            }
        }

        // monitor 설치 — 방식 1·2만. method3 (보류) 는 ⌘ keyUp 으로만 닫힘.
        if mode != .method3 {
            outsideClickMonitor.install()
            installLocalClickMonitor()
            installPopoverKeyMonitor(mode: mode)
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
            },
            handleClipCopy: { [weak self] idx in
                await self?.handleClipCopy(at: idx)
            }
        )
    }

    private func installLocalClickMonitor() {
        removeLocalClickMonitor()
        // TASK-025 — 외부 click 시 NSTextField first responder *복원* 방향.
        localClickMonitor = PopoverPanel.installSearchFirstResponderRestoreMonitor(panel: panel)
    }

    private func removeLocalClickMonitor() {
        if let m = localClickMonitor {
            NSEvent.removeMonitor(m)
            localClickMonitor = nil
        }
    }

    /// TASK-025 — popover 키 라우팅 monitor (이전 escapeKeyMonitor 의 superset).
    private func installPopoverKeyMonitor(mode: PopoverInvocationMode) {
        removePopoverKeyMonitor()
        popoverKeyMonitor = PopoverPanel.installPopoverKeyEventMonitor(
            panel: panel,
            viewModel: viewModel,
            mode: mode,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx in
                await self?.handleClipPaste(at: idx)
            },
            handleClipCopy: { [weak self] idx in
                await self?.handleClipCopy(at: idx)
            }
        )
    }

    private func removePopoverKeyMonitor() {
        if let m = popoverKeyMonitor {
            NSEvent.removeMonitor(m)
            popoverKeyMonitor = nil
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

    /// TASK-024 — 클립 copy 흐름 (⌘+C 단축키). PopoverPanel.performCopyFlow 헬퍼로 위임. performPasteFlow 와 동일 패턴 (mode 만 `.copyBack` 강제).
    private func handleClipCopy(at idx: Int) async {
        let label = currentMode.map { "PopoverWindow(\(String(describing: $0)))" } ?? "PopoverWindow"
        await PopoverPanel.performCopyFlow(
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
