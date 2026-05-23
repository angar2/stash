// stash 워드마크 (검색바 외부 위) + 검색 인풋 (안에 우측 "전체 삭제" 텍스트 버튼) — popover.jsx L313-373 100% 정합
import SwiftUI

struct PopoverHeaderView: View {
    @Bindable var viewModel: ClipsViewModel
    /// 방식 2 — popover form은 동일 노출, 검색 입력 + 전체 삭제 클릭 모두 차단 (TASK-018).
    let mode: PopoverInvocationMode
    @State private var deleteAllHovered: Bool = false
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 검색 박스 포커스 보더/ring 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue
    /// TASK-043 — 일시정지/재개 버튼 hover state.
    @State private var captureToggleHovered: Bool = false
    /// TASK-058 — popover 유지 모드 토글 버튼 hover state.
    @State private var keepOpenToggleHovered: Bool = false

    /// 방식 2일 때 true — 검색바·"전체 삭제" 등 인터랙션 일체 차단.
    private var isInteractionDisabled: Bool { mode == .method3 }

    var body: some View {
        let _ = accentColorModeRaw  // TASK-053 SwiftUI 의존성 등록
        return VStack(alignment: .leading, spacing: 0) {
            wordmarkRow
            searchContainer
        }
    }

    // 워드마크 행 — popover.jsx L317-326 (padding 8 12 2)
    // 우측 trailing에 '전체 삭제' 버튼 위치 (지크 요구 — 검색부 내부에서 워드마크 우측으로 이동).
    private var wordmarkRow: some View {
        HStack(spacing: DesignTokens.Spacing.wordmarkIconLabelGap) {
            TrayIconView(full: true, size: 14)
                .foregroundStyle(DesignTokens.Colors.accent)
            Text("stash")
                .font(DesignTokens.Typography.brandWordmark)
                .foregroundStyle(DesignTokens.Colors.labelWordmark)
                .tracking(-0.25)
            Spacer()
            if viewModel.clips.count > 0 {
                Text(String(localized: "search.deleteAll"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(deleteAllHovered ? DesignTokens.Colors.searchDeleteAllLabelHover : deleteAllColor)
                    .contentShape(Rectangle())
                    .onHover { isHover in
                        guard !isInteractionDisabled else { return }
                        deleteAllHovered = isHover
                    }
                    .onTapGesture {
                        guard !isInteractionDisabled else { return }
                        Task { await viewModel.deleteAllExceptPinned() }
                    }
                    .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: deleteAllHovered)
                    .allowsHitTesting(!isInteractionDisabled)
            }
            // TASK-043 — 클립보드 수집 일시정지/재개 버튼. clips.count 무관 항상 표시. 아이콘만 분기 (pause ↔ play), 색상은 *전체 삭제* 텍스트와 동일 회색 흐름 정합.
            captureToggleButton
            // TASK-058 — popover 유지 모드 토글 버튼. 일시정지 버튼 오른쪽. ON 시 paste/copy 후 popover close skip (F-011).
            keepOpenToggleButton
        }
        .padding(.horizontal, DesignTokens.Spacing.wordmarkPaddingHorz)
        .padding(.top, DesignTokens.Spacing.wordmarkPaddingTop)
        .padding(.bottom, DesignTokens.Spacing.wordmarkPaddingBottom)
    }

    /// TASK-043 — 워드마크 행 오른쪽 끝 *클립보드 수집 토글* 버튼. 활성=`pause.fill` / 비활성=`play.fill`. 색상은 두 경우 모두 기본 회색 (label-tertiary 흐름). 시각 강조는 메뉴바 트레이 red dot 가 단일 진입점.
    private var captureToggleButton: some View {
        Image(systemName: viewModel.captureEnabled ? "pause.fill" : "play.fill")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(captureToggleHovered ? DesignTokens.Colors.searchDeleteAllLabelHover : DesignTokens.Colors.searchDeleteAllLabel)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(captureToggleHovered ? Color.white.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHover in
                guard !isInteractionDisabled else { return }
                captureToggleHovered = isHover
            }
            .onTapGesture {
                guard !isInteractionDisabled else { return }
                viewModel.toggleCapture()
            }
            .help(viewModel.captureEnabled ? String(localized: "tooltip.capture.disable") : String(localized: "tooltip.capture.enable"))
            .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: captureToggleHovered)
            .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: viewModel.captureEnabled)
            .allowsHitTesting(!isInteractionDisabled)
            .padding(.leading, 4)
    }

    /// TASK-058 — popover 유지 모드 토글 버튼. 일시정지 버튼 옆 (간격 4pt). *action-icon 패턴* (pause/play 정합) — OFF=`lock.fill` (지금 누르면 잠금 액션) / ON=`lock.open` (지금 누르면 잠금 해제 액션). fill 분기 만 (회색 단일 톤 + hover 4pt 라운드). 영속성 = 세션 한정 — `PopoverWindow.hide()` 시 OFF 리셋. ON 시 외부 클릭 / ESC / 트레이 재클릭 / ⌘⇧V 재호출 모두 차단 — 본 버튼 클릭만 잠금 해제 진입점. FEATURES F-011 단일 진실.
    private var keepOpenToggleButton: some View {
        Image(systemName: viewModel.keepOpenAfterAction ? "lock.open" : "lock.fill")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(keepOpenToggleHovered ? DesignTokens.Colors.searchDeleteAllLabelHover : DesignTokens.Colors.searchDeleteAllLabel)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(keepOpenToggleHovered ? Color.white.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHover in
                guard !isInteractionDisabled else { return }
                keepOpenToggleHovered = isHover
            }
            .onTapGesture {
                guard !isInteractionDisabled else { return }
                viewModel.toggleKeepOpenAfterAction()
            }
            .help(viewModel.keepOpenAfterAction ? String(localized: "tooltip.keepOpen.disable") : String(localized: "tooltip.keepOpen.enable"))
            .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: keepOpenToggleHovered)
            .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: viewModel.keepOpenAfterAction)
            .allowsHitTesting(!isInteractionDisabled)
            .padding(.leading, 4)
    }

    // 검색 컨테이너 — popover.jsx L329-373 (padding 4 6 8)
    // PlainNSTextField (NSTextField wrap) 사용 — SwiftUI .focused / @FocusState는 NSPanel(.nonactivatingPanel) + KeyablePanel 환경에서 first responder 처리 불안정. NSTextField는 자체 NSResponder chain.
    private var searchContainer: some View {
        HStack(spacing: DesignTokens.Spacing.searchBoxIconGap) {
            // 검색 아이콘 (좌측)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(searchIconColor)
                .frame(width: 13, height: 13)

            // 인풋 — NSTextField wrap.
            // TASK-025 — onFocusChange 콜백 본문 비움. 검색바 always-active 정책 — first responder 진입/이탈은 시각 분기 없음.
            // 방식 2 (method3) — isEnabled=false로 NSTextField editable/selectable 비활성.
            PlainNSTextField(
                text: $viewModel.searchQuery,
                placeholder: searchPlaceholder,
                placeholderAttributed: nil,
                font: .systemFont(ofSize: 12.5, weight: .medium),
                textColor: NSColor.labelColor,
                onFocusChange: { _ in
                    // TASK-025 — body 비움. always-active 정책 정합.
                },
                isEnabled: !isInteractionDisabled
            )
            // TASK-061 — 디바운스 적용 (`Constants.searchDebounce = 100ms`, plan F-009). 이전 `Task { await viewModel.performSearch() }` 즉시 호출이 매 키 입력마다 notification 다중 발행 → setFrame race → popover height oscillation.
            .onChange(of: viewModel.searchQuery) { _, _ in
                viewModel.scheduleSearch()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.searchBoxPaddingHorz)
        .frame(height: DesignTokens.Spacing.searchBoxHeight)
        .background(searchBoxBackground)
        .overlay(searchBoxBorder)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous))
        .padding(.horizontal, DesignTokens.Spacing.searchContainerPaddingHorz)
        .padding(.top, DesignTokens.Spacing.searchContainerPaddingTop)
        .padding(.bottom, DesignTokens.Spacing.searchContainerPaddingBottom)
        // TASK-025 — `.onHover { setFocusZone(.search) }` 블록 폐기. 검색바 hover 시각 변화 없음 (always-active).
    }

    private var searchPlaceholder: String {
        return String(localized: "search.placeholder")
    }

    /// TASK-025 — 검색바 icon 색상 단일화 (focusZone == .search 분기 제거).
    private var searchIconColor: SwiftUI.Color {
        DesignTokens.Colors.searchIconInactive
    }

    private var deleteAllColor: SwiftUI.Color { DesignTokens.Colors.searchDeleteAllLabel }

    /// TASK-025 — 단일 배경. hover 그라디언트 / searchInputActive 분기 폐기.
    @ViewBuilder
    private var searchBoxBackground: some View {
        DesignTokens.Colors.searchBoxBg
    }

    /// TASK-025 — `searchQuery.isEmpty` 분기. 빈 입력 = 기본 회색 테두리 / 1자 이상 = 파란 강조 테두리.
    @ViewBuilder
    private var searchBoxBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous)
            .stroke(
                viewModel.searchQuery.isEmpty
                    ? DesignTokens.Colors.searchBoxBorder
                    : DesignTokens.Colors.searchBoxFocusedBorder,
                lineWidth: 0.5
            )
    }

    // TASK-025 — `searchFocusedRing` ViewBuilder 폐기. focus ring 시각 제거.
}

// 기존 SearchBarView 명명 호환 (HistoryPopover에서 사용)
typealias SearchBarView = PopoverHeaderView
