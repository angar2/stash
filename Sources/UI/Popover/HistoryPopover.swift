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

    // TASK-053 — 콘텐츠 색상 모드 변경 시 popover body 재평가 트리거. 자식 view (ClipRowView / SearchBarView 등) 도 각자 @AppStorage 박아 자체 추적.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue
    /// TASK-073 — 앱 언어 변경 시 popover body 재평가 → 모든 자식 view 의 `String(localized:)` 호출이 새 언어로 lookup.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        // arrow tail은 다음 fix 사이클에서 panel 외부 별도 NSView로 박음 (NSVisualEffectView cornerRadius 안에서 잘리는 문제 회피)
        let _ = accentColorModeRaw  // SwiftUI 의존성 등록
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return popoverBody
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
        // TASK-054 fix-2 — root width 고정 (`frame(width: popoverWidth)`) → `maxWidth: .infinity` 로 전환. 시스템 표준 NSWindow resize 도입 (TASK-054 fix-1) 으로 NSPanel width 가 동적이라 *SwiftUI body 가 NSPanel.contentView fill* 되어야 자식들 (검색바·클립행·핀행·환경설정행·힌트바) 의 `Spacer()`·`frame(maxWidth: .infinity, alignment: .leading)` 패턴이 *부모 폭 따라 좌/우 정렬* 자연 적용.
        .padding(DesignTokens.Spacing.popoverPadding)
        // TASK-080 — popover root 외부 bottom spacing 추가. 마지막 자식 (hintBar OFF=preferencesRow / ON=KeyboardHintsView) ↔ popover 외곽 시각 거리를 좌우 outer 패턴 (popoverPadding + rowOuterHorzInset/hintsBarPaddingHorz) 과 동일하게 정합. 자식 자체 padding 손대지 X → background 두께 변경 0.
        .padding(.bottom, DesignTokens.Spacing.popoverPaddingBottomExtra)
        .frame(maxWidth: .infinity)
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
        // TASK-054 fix-2 — arrow tail bar 도 popover 전체 폭 따라 늘어남. width 동적 시 button 중심 anchor 시각은 windowDidResize 가 `currentAnchorOffsetX` 재계산.
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clips area
    // TASK-061 — 분기 폐기. 이전 isEmptyState / isSearchEmptyResult 분기 시 *별 view (emptyState / searchEmptyResult)* 가 clipsList 자리 대체 박힘 → `.frame(height: effectiveClipListHeight)` 적용 X → autoFit OFF 인데도 clipList 영역 size 변동 → 외곽 + 상단/하단 자식 위치 변동.
    // 항상 clipsList 박음 → `.frame(height: effectiveClipListHeight)` 항상 적용 → autoFit OFF = N×rowHeight 고정 보장. 빈 영역 (visibleClips.isEmpty) 은 clipsList 안 ScrollView 가 자연 처리 (스크롤 없이 빈 영역).
    // 검색 결과 0건 시각 안내 (점 "·") 는 clipsList 내부 overlay 로 처리.
    private var clipsArea: some View {
        clipsList
    }

    private var clipsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: DesignTokens.Spacing.rowGap) {
                    ForEach(Array(visibleClips.enumerated()), id: \.element.id) { idx, clip in
                        // TASK-060 — closure 안 capture 용 clip.id. `.equatable()` (TASK-037 fix-15b) 가 동일 clip + 동일 isSelected 시 view instance 재사용 → 기존 closure 의 stale idx 잔존. 외부 복사로 reload 시 행 순서 변동 후 *시각 위치 ≠ closure idx* misalign 발생. 호출 시점에 visibleClips 에서 clip.id 로 현재 idx 다시 찾아 정확 호출.
                        let clipId = clip.id
                        ClipRowView(
                            clip: clip,
                            isSelected: idx == viewModel.selectedIdx,
                            isFocused: viewModel.focusZone == .clip,
                            isFlashing: clip.id == viewModel.flashedClipId,
                            mode: mode,
                            searchQuery: viewModel.searchQuery,  // TASK-035 — 일반 히스토리 영역 매칭 강조 prop 전달.
                            onClick: { Task { @MainActor in
                                guard let currentIdx = viewModel.visibleClips.firstIndex(where: { $0.id == clipId }) else { return }
                                await handleClipPaste(currentIdx, .clip)
                            } },
                            onHover: {
                                guard let currentIdx = viewModel.visibleClips.firstIndex(where: { $0.id == clipId }) else { return }
                                viewModel.setSelectedIdx(currentIdx)
                            },
                            onTogglePin: { Task { @MainActor in
                                // TASK-060 — id 기반 메서드 직접 호출 (기존 `togglePin(id:trackSelection:)` 존재).
                                await viewModel.togglePin(id: clipId, trackSelection: .clip)
                            } },
                            onDelete: { Task { @MainActor in
                                guard let currentIdx = viewModel.visibleClips.firstIndex(where: { $0.id == clipId }) else { return }
                                await viewModel.delete(at: currentIdx)
                            } },
                            onHoverEnter: { viewModel.hoverEnterRow(id: clipId) },  // TASK-055 — hover 임계 timer 시작.
                            onHoverExit: { viewModel.hoverExitRow(id: clipId) }    // TASK-055 — 같은 행 이탈 시 timer cancel.
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
            // TASK-061 — 빈 영역 안내 (emptyState / searchEmptyResult) 자체 폐기 (사용자 요구). visibleClips.isEmpty 시 clipsList 영역 빈 채로 박힘.
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

    // TASK-061 — emptyState / searchEmptyResult view 폐기 (사용자 요구). visibleClips.isEmpty 시 clipsList 영역 빈 채로 박힘.

    // Pin 행 — popover.jsx L422-467
    private var pinRow: some View {
        // TASK-018 Phase 8 — focusZone 단일 진실 소스. pinSidebarOpen은 사이드 펼침 상태이며 popover 안 행 selection과 분리. focusZone == .pin 일 때만 selected.
        let selected = viewModel.focusZone == .pin
        return HStack(spacing: DesignTokens.Spacing.rowInnerGap) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.accent)
                .rotationEffect(.degrees(45))
            Text(L10n("pin.row.title"))
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
                    .fill(DesignTokens.Colors.keycapBg)
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
            // TASK-053 fix-1 — 환경설정 톱니 아이콘은 강조 색상 추종 X. 선택/비선택 무관 항상 `preferencesRow` 회색 톤 (텍스트와 동일). 선택 시각 구분은 행 bg 그라데이션 만으로.
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.preferencesRow)
            Text(L10n("preferences.row"))
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
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isInteractionDisabled else { return }
            onOpenSettings()
        }
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
