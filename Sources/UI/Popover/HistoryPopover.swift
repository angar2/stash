// 1·2·3 popover 공통 content (TASK-018) — popover.jsx 100% 정합. 워드마크 + 검색바 + 클립 리스트 + Pin 행 + 환경설정 행 (휴지통 X) + 힌트바.
// 방식 2도 1·3과 동일 form 노출 / 검색바·환경설정·전체 삭제·핀·X 클릭은 모두 비활성 (입력 차단).
import SwiftUI
import AppKit

struct HistoryPopover: View {
    @Bindable var viewModel: ClipsViewModel
    let mode: PopoverInvocationMode
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    /// TASK-037 fix-1 — @AppStorage 로 UserDefaults 추적. SwiftUI 가 KVO 자동 감지 → 슬라이더/체크박스 변경 시 body 재계산 → .frame(maxHeight:) 실시간 반영.
    @AppStorage("clipsPerPage") private var clipsPerPage: Int = Constants.clipsPerPageDefault
    @AppStorage("autoFitClipListHeight") private var autoFitClipListHeight: Bool = false
    /// TASK-052 — 단축키 설명 표시 토글. OFF 시 `KeyboardHintsView` if 분기 false → 전체 비표시 + popover height 자동 축소.
    @AppStorage("hintBarVisible") private var hintBarVisible: Bool = true
    /// Window가 주입 — popover dismiss + 이전 frontmost 앱 복원 + 활성화 대기 + paste 흐름 캡슐화 (Bug 4·5 fix).
    /// HistoryPopover는 idx + zone 전달 → Window 측이 hide → restore → sleep → viewModel.paste(at:zone:) 순서 보장.
    /// TASK-028 — 본체 행 paste 호출 시 `zone: .clip` 명시 전달. hide() 흐름의 focusZone 리셋 영향 차단.
    let handleClipPaste: @MainActor (Int, FocusZone) async -> Void
    let anchorOffsetX: CGFloat?  // 방식 1 arrow tail 위치 (popover 좌표계 안 button center x)

    private var hasPinned: Bool { !viewModel.pinnedClips.isEmpty }
    // TASK-019 fix 6차 — `filter { !$0.isPinned }` 제거. 핀 항목도 본체 일반 히스토리에 *시간순 자연 노출* (FEATURES F-002 / §3-4 정합).
    // TASK-015 에서 박힌 줄. fix 1~5차 동안 ClipsViewModel.visibleClips 만 보면서 못 잡았던 root cause.
    private var visibleClips: [Clip] { viewModel.visibleClips }
    /// 방식 2 — 검색·환경설정·전체 삭제 등 일체 인터랙션 차단 (TASK-018, 결정 1-A).
    private var isInteractionDisabled: Bool { mode == .method3 }

    init(
        viewModel: ClipsViewModel,
        mode: PopoverInvocationMode,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        handleClipPaste: @escaping @MainActor (Int, FocusZone) async -> Void,
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
            // 1·2·3 동일 form — 방식 2도 검색바·환경설정 노출 (입력 비활성, TASK-018).
            PopoverHeaderView(viewModel: viewModel, mode: mode)
            clipsArea
            if hasPinned {
                pinRow
            }
            preferencesRow
            // TASK-052 — 단축키 설명 표시 토글 OFF 시 KeyboardHintsView 전체 (상단 Divider 포함) 비표시. SettingsViewModel.setHintBarVisible 가 발행하는 displayLayoutDidChange notification 으로 PopoverWindow._performRefreshFrame 가 fittingSize 재측정 → NSPanel.setFrame 으로 popover height 자동 축소.
            if hintBarVisible {
                KeyboardHintsView(mode: mode, accessibilityGranted: viewModel.accessibilityGranted)
            }
        }
        // TASK-037 fix-12 — `.padding(6).frame(width: 380)` 순서. outer width = popoverWidth (380) 고정 / inner content = popoverWidth - 12 (368). SwiftUI body intrinsic.width = NSPanel.frame.width 매치 — 자식 view 잘림/빈 영역 차단.
        .padding(DesignTokens.Spacing.popoverPadding)
        .frame(width: DesignTokens.WindowSize.popoverWidth)
        // TASK-027 fix — coordinateSpace + ActiveRowFramePreferenceKey 수신을 popoverBody root 에 박음 (ScrollView 박으면 검색바/Pin/환경설정/힌트 offset 어긋남).
        // ClipRowView 의 GeometryReader 가 게시하는 frame 이 NSPanel contentView top 기준 (top-down) 이 되어 NSPanel.frame.height 와 정합.
        .popoverClipDetailHook(viewModel: viewModel, activeZone: .clip)
        // NSVisualEffectView가 panel.contentView 레벨에서 base blur + vibrancy 100% 담당. SwiftUI body는 완전 투명.
        .background(Color.clear)
        // Bug 3-2 fix v2 — popover 빈 영역 클릭으로 deactivateSearchInput 박았던 .background { Color.clear.onTapGesture }
        // 패턴은 자식 view 클릭을 모두 흡수하는 부작용이 있어 제거. 자동 해제는 setFocusZone 진입 시 처리 (hover 경로).
        // 빈 영역 클릭 deactivate는 별도 NSEvent 모니터로 우회 검토 — 본 task 범위 밖.
        .task { await viewModel.reload() }
        // 단축키 처리: SwiftUI .onKeyPress가 NSPanel(.nonactivatingPanel) 환경에서 발화 안 해
        // KeyablePanel.keyDown override + PopoverPanel.installKeyDownHandler에서 PopoverHotkey enum 매칭으로 처리 (TASK-017).
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
                            searchQuery: viewModel.searchQuery,  // TASK-035 — 일반 히스토리 영역 매칭 강조 prop 전달.
                            onClick: { Task { @MainActor in await handleClipPaste(idx, .clip) } },  // Bug 4·5 fix — Window 측에서 dismiss + 이전 앱 복원 + paste 캡슐화. TASK-028 — 본체 행이라 zone=.clip 고정.
                            onHover: { viewModel.setSelectedIdx(idx) },
                            onTogglePin: { Task { await viewModel.togglePin(at: idx) } },
                            onDelete: { Task { await viewModel.delete(at: idx) } }
                        )
                        // TASK-037 fix-15b — Equatable conformance + .equatable() → SwiftUI 가 변경된 행만 re-render. 호버 응답 빠름.
                        .equatable()
                        .id(clip.id)
                    }
                }
                // TASK-018 Phase 7 — 검색·Pin·환경설정 행과 동일 좌우 outer inset.
                .padding(.horizontal, DesignTokens.Spacing.rowOuterHorzInset)
            }
            // TASK-037 fix-2 — `.frame(maxHeight:)` (상한) → `.frame(height:)` (명시 고정).
            // 상한만 박으면 autoFit OFF + visibleCount 적은 케이스 (예: N=20, 클립 4개) 에서 SwiftUI 가 4행 분만 차지 → 컨테이너 N×rowHeight 안 늘어남.
            // height 명시 박으면 컨테이너가 항상 N×rowHeight (autoFit OFF) 또는 visibleCount×rowHeight (autoFit ON) 차지.
            .frame(height: ClipsViewModel.effectiveClipListHeight(
                visibleCount: visibleClips.count,
                clipsPerPage: clipsPerPage,
                autoFit: autoFitClipListHeight,
                hasPinned: hasPinned,
                hintBarVisible: hintBarVisible
            ))
            // TASK-019 fix 6차 — anchor:nil 모델. multiline 행 가변 height 무관. SwiftUI 가 *id 가 visible 안이면 변화 X, 밖이면 가장 가까운 위치로 자동 끌어옴*. 커서 항상 가시.
            .onChange(of: viewModel.pendingScrollToId) { _, newId in
                guard let id = newId else { return }
                withAnimation(.easeInOut(duration: DesignTokens.Animation.scrollFollowDuration)) {
                    proxy.scrollTo(id)
                }
                viewModel.consumePendingScroll()
            }
            // TASK-027 — coordinateSpace + onPreferenceChange 는 popoverBody root 로 이동 (Y 좌표계 정합 fix).
        }
    }

    // 빈 상태 — TASK-037 단순화. 라운드 컨테이너 + 트레이 아이콘 제거. 멘트 2종 (제목 + 보조) only.
    private var emptyState: some View {
        VStack(spacing: 0) {
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
        // TASK-018 Phase 8 — focusZone 단일 진실 소스. pinSidebarOpen은 사이드 펼침 상태이며 popover 안 행 selection과 분리. focusZone == .pin 일 때만 selected.
        let selected = viewModel.focusZone == .pin
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
            // TASK-019 — Pin 사이드바 토글 단축키 안내 키캡. mode == .method3 (보류) 시도 시각만 노출 (단축키 자체 차단).
            pinRowShortcutKeycap("⌘B")
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
            if mode != .method3 {
                if isHover {
                    // TASK-018 Phase 8 — focusZone 단일 진실 소스. hover 진입 시 .pin 으로 변경 → 다른 행(클립·검색·환경설정) 동시 활성 차단.
                    viewModel.setFocusZone(.pin)
                    viewModel.pinRowHoverEnter()
                } else {
                    viewModel.pinRowHoverExit()
                }
            }
        }
        // TASK-019 fix 2차 — Pin Row 클릭 토글 *제거* (사용자 결정 M1). 트리거는 hover 200ms + ⌘B 단축키 2가지만.
        // TASK-018 Phase 7 — 검색·클립·환경설정 행과 동일 좌우 outer inset (hover background 가로 폭 통일).
        .padding(.horizontal, DesignTokens.Spacing.rowOuterHorzInset)
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

    // 행 우측 단축키 안내 키캡 (TASK-019 핀 행 ⌘B / TASK-029 환경설정 행 ⌘, 공용) — DesignTokens 의 키캡 토큰 통합.
    private func pinRowShortcutKeycap(_ label: String) -> some View {
        Text(label)
            .font(DesignTokens.Typography.pinRowKeycap)
            .foregroundStyle(DesignTokens.Colors.pinRowHeader.opacity(0.7))
            .padding(.horizontal, DesignTokens.Spacing.keycapPaddingHorz)
            .padding(.vertical, DesignTokens.Spacing.keycapPaddingVert)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.pinRowKeycap, style: .continuous)
                    .fill(DesignTokens.Colors.pinRowKeycapBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.pinRowKeycap, style: .continuous)
                    .stroke(DesignTokens.Colors.divider, lineWidth: DesignTokens.Spacing.keycapStrokeWidth)
            )
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
            // TASK-029 — 환경설정 진입 단축키 ⌘, 시각 노출. 핀 행 ⌘B 키캡과 동일 스타일.
            pinRowShortcutKeycap("⌘,")
            // TASK-029 — 핀 행 우측 chevron 자리만큼 invisible spacer. 키캡 우측 끝 x 좌표를 핀 행 ⌘B 키캡과 정합 (수직 정렬 라인 일치).
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .hidden()
        }
        .padding(.horizontal, DesignTokens.Spacing.preferencesRowPadHorz)
        // TASK-029 — 핀 행 키캡과 행 높이 일치 (수직 가운데 정렬 정합) 위해 frame/padding 을 핀 행과 통일.
        .frame(height: DesignTokens.Spacing.pinRowHeight)
        .padding(.vertical, DesignTokens.Spacing.pinRowMarginVert)
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
        .onTapGesture {
            guard !isInteractionDisabled else { return }
            onOpenSettings()
        }
        // TASK-030 — 환경설정 행에 손가락 cursor. method3 비활성 분기 정합.
        .pointingHandCursor(enabled: !isInteractionDisabled)
        .onHover { isHover in
            guard !isInteractionDisabled else { return }
            if isHover {
                viewModel.setFocusZone(.settings)
            }
        }
        .allowsHitTesting(!isInteractionDisabled)
        // TASK-018 Phase 7 — 검색·클립·Pin 행과 동일 좌우 outer inset (hover background 가로 폭 통일).
        .padding(.horizontal, DesignTokens.Spacing.rowOuterHorzInset)
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
