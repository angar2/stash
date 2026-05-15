// 방식 1 (NSPopover) + 방식 3 (NSPanel)이 공유하는 popover content
// popover.jsx 100% 정합 — 워드마크 + 검색바 + 클립 리스트 + Pin 행 + 환경설정 행 (휴지통 X) + 힌트바
// 방식 2 = 미니멀 (검색·환경설정·삭제 버튼 X / 클립 리스트 + Pin 행 + 힌트바만)
import SwiftUI
import AppKit

struct HistoryPopover: View {
    @Bindable var viewModel: ClipsViewModel
    let mode: PopoverInvocationMode
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    /// Window가 주입 — popover dismiss + 이전 frontmost 앱 복원 + 활성화 대기 + paste 흐름 캡슐화 (Bug 4·5 fix).
    /// HistoryPopover는 idx만 전달하면 Window 측이 hide → restore → sleep → viewModel.paste 순서 보장.
    let handleClipPaste: @MainActor (Int) async -> Void
    let anchorOffsetX: CGFloat?  // 방식 1 arrow tail 위치 (popover 좌표계 안 button center x)

    private var isFull: Bool { mode != .method2 }
    private var hasPinned: Bool { !viewModel.pinnedClips.isEmpty }
    private var visibleClips: [Clip] { viewModel.filteredClips.filter { !$0.isPinned } }

    init(
        viewModel: ClipsViewModel,
        mode: PopoverInvocationMode,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        handleClipPaste: @escaping @MainActor (Int) async -> Void,
        anchorOffsetX: CGFloat? = nil
    ) {
        self.viewModel = viewModel
        self.mode = mode
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
        self.handleClipPaste = handleClipPaste
        self.anchorOffsetX = anchorOffsetX
    }

    var body: some View {
        // arrow tail은 다음 fix 사이클에서 panel 외부 별도 NSView로 박음 (NSVisualEffectView cornerRadius 안에서 잘리는 문제 회피)
        popoverBody
    }

    private var popoverBody: some View {
        VStack(spacing: 0) {
            if isFull {
                PopoverHeaderView(viewModel: viewModel)
            }
            clipsArea
            if hasPinned {
                pinRow
            }
            if isFull {
                preferencesRow
            }
            KeyboardHintsView(mode: mode)
        }
        .frame(width: DesignTokens.WindowSize.popoverWidth)
        .padding(DesignTokens.Spacing.popoverPadding)
        // NSVisualEffectView가 panel.contentView 레벨에서 base blur + vibrancy 100% 담당. SwiftUI body는 완전 투명.
        .background(Color.clear)
        // Bug 3-2 fix v2 — popover 빈 영역 클릭으로 deactivateSearchInput 박았던 .background { Color.clear.onTapGesture }
        // 패턴은 자식 view 클릭을 모두 흡수하는 부작용이 있어 제거. 자동 해제는 setFocusZone 진입 시 처리 (hover 경로).
        // 빈 영역 클릭 deactivate는 별도 NSEvent 모니터로 우회 검토 — 본 task 범위 밖.
        .task { await viewModel.reload() }
        .onKeyPress(.upArrow) {
            viewModel.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelectionDown()
            return .handled
        }
        .onKeyPress(.return) {
            if viewModel.focusZone == .search && !viewModel.searchInputActive {
                viewModel.activateSearchInput()
                return .handled
            }
            // Bug 4·5 fix — Enter paste도 dismiss + 이전 앱 복원 흐름 적용 (Window 측 handleClipPaste).
            let idx = viewModel.selectedIdx
            Task { @MainActor in await handleClipPaste(idx) }
            return .handled
        }
        .onKeyPress(.escape) {
            if viewModel.searchInputActive {
                viewModel.deactivateSearchInputAndClear()
                return .handled
            }
            if viewModel.pinSidebarOpen {
                viewModel.collapsePinSidebar()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if !viewModel.pinnedClips.isEmpty && mode != .method2 {
                viewModel.expandPinSidebarImmediately()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.leftArrow) {
            if viewModel.pinSidebarOpen {
                viewModel.collapsePinSidebar()
                return .handled
            }
            return .ignored
        }
        .onKeyPress("1") {
            guard !viewModel.searchInputActive else { return .ignored }
            viewModel.moveSelectionUp()
            return .handled
        }
        .onKeyPress("2") {
            guard !viewModel.searchInputActive else { return .ignored }
            viewModel.moveSelectionDown()
            return .handled
        }
        .onKeyPress("p") {
            guard !viewModel.searchInputActive else { return .ignored }
            Task { await viewModel.togglePin(at: viewModel.selectedIdx) }
            return .handled
        }
    }

    // MARK: - Arrow tail (방식 1 only) — popover.jsx L301-310 정합
    private func arrowTail(offsetX: CGFloat) -> some View {
        let tailWidth: CGFloat = 14
        let tailHeight: CGFloat = 8
        let leadingPad = max(0, offsetX - tailWidth / 2)
        return HStack(spacing: 0) {
            Spacer().frame(width: leadingPad)
            ArrowTailShape()
                .fill(DesignTokens.Colors.popoverBackground)
                .overlay(
                    ArrowTailShape()
                        .stroke(DesignTokens.Shadow.popoverOuterStroke, lineWidth: 0.5)
                )
                .frame(width: tailWidth, height: tailHeight)
            Spacer()
        }
        .frame(width: DesignTokens.WindowSize.popoverWidth)
    }

    // MARK: - Clips area
    @ViewBuilder
    private var clipsArea: some View {
        if viewModel.isEmptyState {
            emptyState
        } else if viewModel.isSearchEmptyResult {
            searchEmptyResult
        } else {
            clipsList
        }
    }

    private var clipsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: DesignTokens.Spacing.rowGap) {
                    ForEach(Array(visibleClips.enumerated()), id: \.element.id) { idx, clip in
                        ClipRowView(
                            clip: clip,
                            isSelected: idx == viewModel.selectedIdx,
                            isFocused: viewModel.focusZone == .clip,
                            isFlashing: clip.id == viewModel.flashedClipId,
                            mode: mode,
                            onClick: { Task { @MainActor in await handleClipPaste(idx) } },  // Bug 4·5 fix — Window 측에서 dismiss + 이전 앱 복원 + paste 캡슐화
                            onHover: { viewModel.setSelectedIdx(idx) },
                            onTogglePin: { Task { await viewModel.togglePin(at: idx) } },
                            onDelete: { Task { await viewModel.delete(at: idx) } }
                        )
                        .id(clip.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: DesignTokens.WindowSize.clipListMaxHeight)
            // Bug 1 fix — 키보드 nav (↑↓·1·2) 만 ScrollView follow 트리거. hover는 selectedIdx만 갱신해 무한 스크롤 루프 차단.
            .onChange(of: viewModel.pendingScrollToId) { _, newId in
                guard let id = newId else { return }
                withAnimation(.easeInOut(duration: DesignTokens.Animation.scrollFollowDuration)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                viewModel.consumePendingScroll()
            }
        }
    }

    // 빈 상태 — popover.jsx L386-406 정합 (84×84 round 컨테이너 + variant 2 SVG 44 + 큰 제목 + 보조)
    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.emptyContainer, style: .continuous)
                    .fill(DesignTokens.Colors.emptyContainerBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.emptyContainer, style: .continuous)
                            .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                    )
                    .frame(width: DesignTokens.Spacing.emptyContainerSize, height: DesignTokens.Spacing.emptyContainerSize)
                TrayIconView(full: false, size: DesignTokens.Spacing.emptyIconSize)
                    .foregroundStyle(DesignTokens.Colors.emptyTrayIcon)
            }
            .padding(.bottom, DesignTokens.Spacing.emptyContainerToTitle)

            Text(String(localized: "empty.title"))
                .font(DesignTokens.Typography.emptyTitle)
                .foregroundStyle(DesignTokens.Colors.emptyTitleColor)
                .padding(.bottom, DesignTokens.Spacing.emptyTitleToHint)

            Text(String(localized: "empty.hint"))
                .font(DesignTokens.Typography.emptyHint)
                .foregroundStyle(DesignTokens.Colors.emptyHintColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.emptyPaddingTop)
        .padding(.bottom, DesignTokens.Spacing.emptyPaddingBottom)
        .padding(.horizontal, DesignTokens.Spacing.emptyPaddingHorz)
        .transition(.opacity)
    }

    // 검색 결과 0 — popover.jsx L382-385 (단순 "·" 점)
    private var searchEmptyResult: some View {
        Text("·")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(DesignTokens.Colors.labelSecondary.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.vertical, 40)
    }

    // Pin 행 — popover.jsx L422-467
    private var pinRow: some View {
        let selected = viewModel.focusZone == .pin || viewModel.pinSidebarOpen
        return HStack(spacing: DesignTokens.Spacing.rowInnerGap) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.accent)
                .rotationEffect(.degrees(45))
            Text(String(localized: "pin.row.title"))
                .font(DesignTokens.Typography.rowHeaderBold)
                .foregroundStyle(DesignTokens.Colors.pinRowHeader)
            Text("\(viewModel.pinnedClips.count)")
                .font(DesignTokens.Typography.pinSidebarBadge)
                .foregroundStyle(DesignTokens.Colors.pinRowHeader)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(DesignTokens.Colors.pinRowBadgeBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
            Image(systemName: viewModel.pinSidebarOpen ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.pinRowHeader.opacity(0.6))
        }
        .padding(.horizontal, DesignTokens.Spacing.pinRowPaddingHorz)
        .frame(height: DesignTokens.Spacing.pinRowHeight)
        .padding(.vertical, DesignTokens.Spacing.pinRowMarginVert)
        .background(pinRowBg(selected: selected))
        .overlay(
            Group {
                if selected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous)
                        .stroke(DesignTokens.Colors.clipRowSelectionBorder, lineWidth: 0.5)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHover in
            if mode != .method2 {
                if isHover { viewModel.pinRowHoverEnter() }
                else { viewModel.pinRowHoverExit() }
            }
        }
    }

    @ViewBuilder
    private func pinRowBg(selected: Bool) -> some View {
        if selected {
            LinearGradient(
                colors: [DesignTokens.Colors.clipRowSelectionTop, DesignTokens.Colors.clipRowSelectionBottom],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            Color.clear
        }
    }

    // 환경설정 행 — popover.jsx L470-497 (톱니 + "환경설정" only / 휴지통 X)
    private var preferencesRow: some View {
        let selected = viewModel.focusZone == .settings
        return HStack(spacing: DesignTokens.Spacing.rowInnerGap) {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(selected ? DesignTokens.Colors.accent : DesignTokens.Colors.preferencesRow)
            Text(String(localized: "preferences.row"))
                .font(DesignTokens.Typography.rowHeader)
                .foregroundStyle(DesignTokens.Colors.preferencesRow)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.preferencesRowPadHorz)
        .frame(height: DesignTokens.Spacing.preferencesRowHeight)
        .padding(.top, DesignTokens.Spacing.preferencesRowMarginTop)
        .background(
            Group {
                if selected {
                    LinearGradient(
                        colors: [DesignTokens.Colors.clipRowSelectionTop, DesignTokens.Colors.clipRowSelectionBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.preferencesRow, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenSettings)
        .onHover { isHover in
            if isHover {
                viewModel.setFocusZone(.settings)
            }
        }
    }
}

// Arrow tail Shape — popover 위쪽 8px 돌출 삼각형 (popover.jsx L301-310 정합)
struct ArrowTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
