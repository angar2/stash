// stash 워드마크 (검색바 외부 위) + 검색 인풋 (안에 우측 "전체 삭제" 텍스트 버튼) — popover.jsx L313-373 100% 정합
import SwiftUI

struct PopoverHeaderView: View {
    @Bindable var viewModel: ClipsViewModel
    /// 방식 2 — popover form은 동일 노출, 검색 입력 + 전체 삭제 클릭 모두 차단 (TASK-018).
    let mode: PopoverInvocationMode
    @State private var deleteAllHovered: Bool = false

    /// 방식 2일 때 true — 검색바·"전체 삭제" 등 인터랙션 일체 차단.
    private var isInteractionDisabled: Bool { mode == .method3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        }
        .padding(.horizontal, DesignTokens.Spacing.wordmarkPaddingHorz)
        .padding(.top, DesignTokens.Spacing.wordmarkPaddingTop)
        .padding(.bottom, DesignTokens.Spacing.wordmarkPaddingBottom)
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
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.performSearch() }
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
