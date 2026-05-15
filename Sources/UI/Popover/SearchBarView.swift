// stash 워드마크 (검색바 외부 위) + 검색 인풋 (안에 우측 "전체 삭제" 텍스트 버튼) — popover.jsx L313-373 100% 정합
import SwiftUI

struct PopoverHeaderView: View {
    @Bindable var viewModel: ClipsViewModel
    @State private var deleteAllHovered: Bool = false

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
                    .onHover { isHover in deleteAllHovered = isHover }
                    .onTapGesture { Task { await viewModel.deleteAllExceptPinned() } }
                    .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: deleteAllHovered)
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

            // 인풋 — NSTextField wrap. focus change → ViewModel activate/deactivate.
            PlainNSTextField(
                text: $viewModel.searchQuery,
                placeholder: searchPlaceholder,
                placeholderAttributed: nil,
                font: .systemFont(ofSize: 12.5, weight: .medium),
                textColor: NSColor.labelColor,
                onFocusChange: { focused in
                    if focused {
                        viewModel.activateSearchInput()
                    } else {
                        viewModel.deactivateSearchInput()
                    }
                }
            )
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.performSearch() }
            }

            // ENTER 키캡 — hover 활성 (focusZone=.search && !active && empty) 시만 visible. opacity로 layout 자리만 유지 (shift 방지).
            KeyCapView(text: "Enter")
                .opacity(showEnterHint ? 1 : 0)
                .allowsHitTesting(false)
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
        .onHover { isHover in
            if isHover {
                viewModel.setFocusZone(.search)
            }
        }
    }

    private var searchPlaceholder: String {
        return String(localized: "search.placeholder")
    }

    /// ENTER 키캡 visible 조건 — hover 활성 + 비활성화 단계 2 + 검색어 비어있음.
    private var showEnterHint: Bool {
        viewModel.focusZone == .search && !viewModel.searchInputActive && viewModel.searchQuery.isEmpty
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
        if viewModel.searchInputActive {
            // 활성화 단계 2 (cursor 깜박) — 배경 = 기본색 (파란 그라디언트 X), 테두리만 파란색 (지크 요구).
            DesignTokens.Colors.searchBoxBg
        } else if viewModel.focusZone == .search {
            // 활성화 단계 1 (hover) — 검색부 전체 파란 그라디언트.
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
