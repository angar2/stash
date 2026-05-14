// stash 워드마크 (검색바 외부 위) + 검색 인풋 (안에 우측 "전체 삭제" 텍스트 버튼) — popover.jsx L313-373 100% 정합
import SwiftUI

struct PopoverHeaderView: View {
    @Bindable var viewModel: ClipsViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmarkRow
            searchContainer
        }
    }

    // 워드마크 행 — popover.jsx L317-326 (padding 8 12 2)
    private var wordmarkRow: some View {
        HStack(spacing: DesignTokens.Spacing.wordmarkIconLabelGap) {
            TrayIconView(full: true, size: 14)
                .foregroundStyle(DesignTokens.Colors.accent)
            Text("stash")
                .font(DesignTokens.Typography.brandWordmark)
                .foregroundStyle(DesignTokens.Colors.labelWordmark)
                .tracking(-0.25)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.wordmarkPaddingHorz)
        .padding(.top, DesignTokens.Spacing.wordmarkPaddingTop)
        .padding(.bottom, DesignTokens.Spacing.wordmarkPaddingBottom)
    }

    // 검색 컨테이너 — popover.jsx L329-373 (padding 4 6 8)
    private var searchContainer: some View {
        HStack(spacing: DesignTokens.Spacing.searchBoxIconGap) {
            // 검색 아이콘 (좌측)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(searchIconColor)
                .frame(width: 13, height: 13)

            // 인풋
            TextField(searchPlaceholder, text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .focused($inputFocused)
                .onTapGesture { viewModel.activateSearchInput() }
                .onChange(of: viewModel.searchQuery) { _, _ in
                    Task { await viewModel.performSearch() }
                }

            // 우측 "전체 삭제" 텍스트 버튼 (clips.count > 0 시만)
            if viewModel.clips.count > 0 {
                Button(action: { Task { await viewModel.deleteAllExceptPinned() } }) {
                    Text(String(localized: "search.deleteAll"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(deleteAllColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.searchBoxPaddingHorz)
        .frame(height: DesignTokens.Spacing.searchBoxHeight)
        .background(searchBoxBackground)
        .overlay(searchBoxBorder)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous))
        .overlay(searchFocusedRing)
        .padding(.horizontal, DesignTokens.Spacing.searchContainerPaddingHorz)
        .padding(.top, DesignTokens.Spacing.searchContainerPaddingTop)
        .padding(.bottom, DesignTokens.Spacing.searchContainerPaddingBottom)
        .onChange(of: viewModel.searchInputActive) { _, newActive in
            inputFocused = newActive
        }
        .onHover { isHover in
            if isHover {
                viewModel.setFocusZone(.search)
            }
        }
    }

    private var searchPlaceholder: String {
        if viewModel.focusZone == .search && !viewModel.searchInputActive {
            return String(localized: "search.placeholder.focused")
        }
        return String(localized: "search.placeholder")
    }

    private var searchIconColor: SwiftUI.Color {
        if viewModel.focusZone == .search {
            return DesignTokens.Colors.accent
        }
        return DesignTokens.Colors.searchIconInactive
    }

    private var deleteAllColor: SwiftUI.Color { DesignTokens.Colors.searchDeleteAllLabel }

    @ViewBuilder
    private var searchBoxBackground: some View {
        if viewModel.focusZone == .search {
            // 클립 행 선택 그라데이션 사용
            LinearGradient(
                colors: [DesignTokens.Colors.clipRowSelectionTop, DesignTokens.Colors.clipRowSelectionBottom],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            DesignTokens.Colors.searchBoxBg
        }
    }

    @ViewBuilder
    private var searchBoxBorder: some View {
        if viewModel.searchInputActive {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous)
                .stroke(DesignTokens.Colors.searchBoxFocusedBorder, lineWidth: 0.5)
        } else if viewModel.focusZone == .search {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous)
                .stroke(DesignTokens.Colors.clipRowSelectionBorder, lineWidth: 0.5)
        } else {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous)
                .stroke(DesignTokens.Colors.searchBoxBorder, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var searchFocusedRing: some View {
        if viewModel.searchInputActive {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.searchBox, style: .continuous)
                .stroke(DesignTokens.Colors.searchBoxFocusedRing, lineWidth: 2)
        }
    }
}

// 기존 SearchBarView 명명 호환 (HistoryPopover에서 사용)
typealias SearchBarView = PopoverHeaderView
