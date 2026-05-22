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

    /// TASK-037 — 디스플레이 환경설정 / visibleClips 변동 시 NSPanel frame 재계산용 NotificationCenter observer 핸들.
    private var displayLayoutObserver: NSObjectProtocol?

    /// TASK-037 fix-9 — 현재 NSHostingView. fittingSize 측정 위해 보관. rebuildHosting 시 갱신.
    private var currentHosting: NSHostingView<AnyView>?

    /// detail panel 총 width — 본문(clipDetailWidth) + 꼭지(clipDetailArrowWidth). NSPanel make / setFrame / originX 계산 모두 본 값 사용 (TASK-027 refactor — 3 곳 중복 계산 통합).
    static var clipDetailTotalWidth: CGFloat {
        DesignTokens.WindowSize.clipDetailWidth + DesignTokens.Spacing.clipDetailArrowWidth
    }

    /// 복사 위치 라인 표시 여부 — Clip extension 단일 진실 소스 호출 (TASK-039 refactor).
    /// `ClipDetailPanelView.copyLocationState` 와 동일 분기 정책 — PanelView 의 SwiftUI 컴퓨티드와 PopoverWindow 의 NSPanel height 계산이 *동일 정책* 으로 일치 보장.
    static func hasCopyLocation(for clip: Clip) -> Bool {
        clip.clipDetailCopyLocationState != nil
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

        // TASK-037 — 디스플레이 환경설정 / visibleClips 변동 알림 구독 → NSPanel frame 동적 재계산.
        displayLayoutObserver = NotificationCenter.default.addObserver(
            forName: ClipsViewModel.displayLayoutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFrame()
            }
        }

    }

    /// TASK-037 fix-13 (fix-15 폐기 후 복원): refreshFrame 본문을 DispatchQueue.main.async 안에 박음.
    /// 사유: @AppStorage / NotificationCenter 동기 호출 시점에는 SwiftUI body 가 *아직 재계산 안 됨* → fittingSize 옛 값 → 영구 mismatch.
    /// async tick = SwiftUI render 완료 후 fittingSize 측정. 매 호출마다 큐 박힘 → 순차 처리 (Task cancel 패턴 폐기 — 드래그 중간 변경 skip 인식 차단).
    private func refreshFrame() {
        guard panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?._performRefreshFrame()
            }
        }
    }

    private func _performRefreshFrame() {
        guard panel.isVisible, let hosting = currentHosting else { return }
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let fitting = hosting.fittingSize

        let prevTop = panel.frame.origin.y + panel.frame.height
        let newOriginX: CGFloat
        let newOriginY: CGFloat
        switch currentMode {
        case .method1:
            newOriginX = panel.frame.origin.x
            newOriginY = prevTop - fitting.height
        case .method2, .method3, .none:
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                newOriginX = visible.maxX - fitting.width - DesignTokens.WindowSize.popoverInsetBottom
                newOriginY = visible.minY + DesignTokens.WindowSize.popoverInsetBottom
            } else {
                newOriginX = panel.frame.origin.x
                newOriginY = panel.frame.origin.y
            }
        }

        let newFrame = NSRect(x: newOriginX, y: newOriginY, width: fitting.width, height: fitting.height)
        // animate:false + display:false → displayIfNeeded — SwiftUI body 재계산 + NSPanel frame transition 충돌 차단.
        panel.setFrame(newFrame, display: false, animate: false)
        panel.displayIfNeeded()
        if pinSidebarPanel.isVisible {
            resizePinSidebarPanel()
        }
        // TASK-044 — refreshFrame async dispatch 종료 직후 first responder 복원 가드. `hosting.invalidateIntrinsicContentSize()` + `layoutSubtreeIfNeeded()` 가 SwiftUI body 재계산 시 NSTextField first responder 상태에 영향 가능 — `trySetSearchFirstResponder` 가 이미 textField 면 no-op, 아니면 복원.
        if let mode = currentMode {
            attemptSearchFirstResponder(mode: mode, reason: "refreshFrame")
        }
        Logger.ui.info("PopoverWindow.refreshFrame — fitting=\(Int(fitting.width), privacy: .public)x\(Int(fitting.height), privacy: .public)")
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
                handleClipPaste: { [weak self] idx, zone in
                    await self?.handleClipPaste(at: idx, zone: zone)
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

    /// TASK-019 / TASK-048 — Pin 사이드바 동적 height 계산. pinnedClips count 기반 + 본체 popoverHeight 미만 상한.
    /// 모든 상수는 `DesignTokens.Spacing` 으로 분리 (`pinSidebarHeaderHeight` / `pinSidebarHeightBottomMargin`).
    /// 식: `header + rows*rowMinHeight + (rows-1)*rowGap + pinSidebarPadding*2`. `LazyVStack(spacing: rowGap)` 이 (count-1) gaps 만 박는 실제 레이아웃 정합.
    /// maxPinnedClips=10 하드 캡이라 10 pins 가 ScrollView 진입 없이 정지 상태 fit. 11+ 케이스 발생 X 이나 식 자체 정확성 가드용 clamp 분기 보존.
    private func computePinSidebarHeight() -> CGFloat {
        Self.computePinSidebarHeight(pinnedCount: viewModel.pinnedClips.count)
    }

    /// pure helper — 테스트 진입점. count 만 받아 동일 식 반환.
    static func computePinSidebarHeight(pinnedCount: Int) -> CGFloat {
        let count = max(1, pinnedCount)
        let rowsBlock = CGFloat(count) * DesignTokens.Spacing.rowMinHeight
            + CGFloat(max(0, count - 1)) * DesignTokens.Spacing.rowGap
        let outerPad = DesignTokens.Spacing.pinSidebarPadding * 2
        let contentH = DesignTokens.Spacing.pinSidebarHeaderHeight + rowsBlock + outerPad
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
        // TASK-039 — zone/PinSidebar 정합 가드. zone == .pin 인데 PinSidebar 비가시 시 emit 거부 (잘못된 anchor=popover 박힘 차단, race fix).
        if request.zone == .pin && !pinSidebarPanel.isVisible {
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
        // detail panel height (TASK-039) — Provider.preferredHeight (본문 자체 raw 추정) + 본문 상하 padding (2 × clipDetailPadding) + 메타 footer + (해당 시) 복사 위치 라인 블록.
        // Provider 본문이 본문 max 도달 시 PanelView 의 ScrollView.frame(maxHeight:) 가 클램프 → 본문은 max content 까지만 확장. 본문 padding + 복사 위치 라인 + 메타 footer 는 항상 박힘.
        let provider = ClipDetailRegistry.provider(for: request.clip)
        let rawContentH = provider?.preferredHeight(for: request.clip) ?? DesignTokens.WindowSize.clipDetailMaxHeight
        let hasLocation = Self.hasCopyLocation(for: request.clip)
        let vPad = 2 * DesignTokens.Spacing.clipDetailPadding // top + bottom 균일 padding
        let extraH = vPad
            + DesignTokens.Spacing.clipMetaFooterHeight
            + (hasLocation ? DesignTokens.Spacing.clipMetaLocationBlockHeight : 0)
        // 본문 max = clipDetailMaxHeight - extraH. content height 가 max 초과면 max 로 클램프 (panel 안 내부 스크롤).
        let contentMaxH = max(DesignTokens.WindowSize.clipDetailMaxHeight - extraH, 0)
        let contentH = min(rawContentH, contentMaxH)
        let detailH = contentH + extraH
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

        // TASK-039 fix — anchor (PinSidebar) height < detailH 케이스 시각 정합. PinSidebar 가 bottom-aligned 인 데다 1 행만 박혀 height 작은 케이스에서 detail panel 이 PinSidebar 위로 크게 확장 → 시각상 *본체 popover 좌측* 처럼 보이는 비정합. detail bottom = anchor bottom 정렬 (PinSidebar bottom-aligned 정합) + arrowOffsetY 재계산.
        if request.zone == .pin && pinSidebarPanel.isVisible && detailH > anchorFrame.height {
            originY = anchorFrame.origin.y // PinSidebar bottom (NSPanel bottom-up 좌표)
            arrowOffsetY = detailH - (rowCenterY_screen - originY)
        }

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
        // TASK-030 — ViewModel isDetailPanelOpen 갱신. pinSidebarHoverExit 가드에서 사용 — 자식 sub-panel 떠 있는 동안 사이드바 자동 닫힘 차단.
        viewModel.isDetailPanelOpen = true
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
        // TASK-030 — ViewModel isDetailPanelOpen 갱신 (사이드바 hover-exit 가드 해제).
        viewModel.isDetailPanelOpen = false
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

        // TASK-044 — SwiftUI NSHostingView 의 lazy layout 강제 동기화. rebuildHosting 직후 NSTextField subview tree 가 박혀있도록 보장 → 직후 호출되는 `findFirstTextField` 가 nil 반환 회귀 차단.
        visualEffectView.layoutSubtreeIfNeeded()

        // TASK-020 — NSApp.activate 호출 제거 (nonactivatingPanel 본질 보존). stash app이 active되지 않으므로 외부 앱이 frontmost 유지 + first responder 보존 + cursor 깜빡임 유지. paste 시점에 CGEvent ⌘V가 외부 앱의 마지막 cursor 위치에 정확히 도달.
        panel.orderFrontRegardless()
        panel.makeKey()

        // TASK-044 — first responder 진입을 헬퍼로 위임. 동기 1회 + async retry 1회. method3 보류는 검색바 isEnabled=false 라 진입 X — 헬퍼 내부에서 가드.
        attemptSearchFirstResponder(mode: mode, reason: "showInternal")

        // monitor 설치 — 방식 1·2만. method3 (보류) 는 ⌘ keyUp 으로만 닫힘.
        if mode != .method3 {
            outsideClickMonitor.install()
            installLocalClickMonitor()
            installPopoverKeyMonitor(mode: mode)
        }

        // 키 이벤트 핸들러 — 모든 mode 설치.
        installKeyDownHandler(mode: mode)

        // TASK-037 — 디스플레이 환경설정 + visibleClips.count 기반 NSPanel frame 동적 갱신 (open 시점 1회).
        refreshFrame()

        Logger.ui.info("PopoverWindow shown — mode=\(String(describing: mode), privacy: .public)")
    }

    private func installKeyDownHandler(mode: PopoverInvocationMode) {
        PopoverPanel.installKeyDownHandler(
            panel: panel,
            viewModel: viewModel,
            mode: mode,
            onDismiss: { [weak self] in self?.hide() },
            handleClipPaste: { [weak self] idx, zone in
                await self?.handleClipPaste(at: idx, zone: zone)
            },
            handleClipCopy: { [weak self] idx, zone in
                await self?.handleClipCopy(at: idx, zone: zone)
            }
        )
    }

    /// TASK-044 — popover open / refreshFrame 후 NSTextField first responder 진입 헬퍼. 동기 1회 + async retry 1회 안전망.
    /// 사유: TASK-025 의 `panel.makeFirstResponder(textField)` 가 SwiftUI NSHostingView 의 lazy layout 시점 이슈로 nil/false 반환 회귀 — 동기 호출이 실패하면 next runloop tick 에서 재시도. 재시도도 실패하면 panel 자체 fallback + warning.
    /// method3 (⌘ hold 보류) 은 검색바 isEnabled=false 라 진입 X — 가드.
    /// `reason` 은 호출 site 식별용 로그 라벨 (showInternal / refreshFrame).
    private func attemptSearchFirstResponder(mode: PopoverInvocationMode, reason: String) {
        guard mode != .method3 else { return }
        if trySetSearchFirstResponder(reason: "\(reason)/sync") {
            return
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.trySetSearchFirstResponder(reason: "\(reason)/async-retry") {
                    return
                }
                Logger.ui.warning("attemptSearchFirstResponder failed after retry — fallback to panel first responder (TASK-044, reason=\(reason, privacy: .public))")
                self.panel.makeFirstResponder(self.panel)
            }
        }
    }

    /// TASK-044 — 1회 진입 시도. 이미 NSTextField 또는 field editor 가 first responder 면 true (no-op). 아니면 `findFirstTextField` 탐색 후 `makeFirstResponder(textField)` 호출 결과 반환.
    @discardableResult
    private func trySetSearchFirstResponder(reason: String) -> Bool {
        guard let textField = PopoverPanel.findFirstTextField(in: panel.contentView) else {
            Logger.ui.debug("trySetSearchFirstResponder: findFirstTextField nil (TASK-044, reason=\(reason, privacy: .public))")
            return false
        }
        if panel.firstResponder === textField || panel.firstResponder === textField.currentEditor() {
            Logger.ui.debug("trySetSearchFirstResponder: already first responder (TASK-044, reason=\(reason, privacy: .public))")
            return true
        }
        let ok = panel.makeFirstResponder(textField)
        Logger.ui.debug("trySetSearchFirstResponder: makeFirstResponder=\(ok, privacy: .public) (TASK-044, reason=\(reason, privacy: .public))")
        return ok
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
            handleClipPaste: { [weak self] idx, zone in
                await self?.handleClipPaste(at: idx, zone: zone)
            },
            handleClipCopy: { [weak self] idx, zone in
                await self?.handleClipCopy(at: idx, zone: zone)
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
    /// TASK-028 — `zone` 명시 파라미터화. 호출 site (HistoryPopover 본체 행 / PinSidebarView 핀 행 / dispatch ⌘V) 가 zone snapshot 박아 전달.
    private func handleClipPaste(at idx: Int, zone: FocusZone) async {
        let label = currentMode.map { "PopoverWindow(\(String(describing: $0)))" } ?? "PopoverWindow"
        await PopoverPanel.performPasteFlow(
            viewModel: viewModel,
            idx: idx,
            zone: zone,
            sourceLabel: label,
            hide: { [weak self] in self?.hide() }
        )
    }

    /// TASK-024 — 클립 copy 흐름 (⌘+C 단축키). PopoverPanel.performCopyFlow 헬퍼로 위임. performPasteFlow 와 동일 패턴 (mode 만 `.copyBack` 강제).
    /// TASK-028 — `zone` 명시 파라미터화.
    private func handleClipCopy(at idx: Int, zone: FocusZone) async {
        let label = currentMode.map { "PopoverWindow(\(String(describing: $0)))" } ?? "PopoverWindow"
        await PopoverPanel.performCopyFlow(
            viewModel: viewModel,
            idx: idx,
            zone: zone,
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
            handleClipPaste: { [weak self] idx, zone in
                await self?.handleClipPaste(at: idx, zone: zone)
            },
            anchorOffsetX: mode == .method1 ? currentAnchorOffsetX : nil
        )
        // TASK-037 fix-9 — hosting 보관 (fittingSize 측정용).
        self.currentHosting = PopoverPanel.mount(view, in: visualEffectView)
    }
}
