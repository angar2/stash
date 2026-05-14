// Pin 사이드 메뉴 — popover.jsx L539-602 100% 정합 (220 width / Liquid Glass / "Pin 목록 · N" UPPERCASE 헤더 + 항목 36 height)
import SwiftUI

struct PinSidebarView: View {
    @Bindable var viewModel: ClipsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.rowGap) {
                    ForEach(Array(viewModel.pinnedClips.enumerated()), id: \.element.id) { idx, clip in
                        pinItem(clip: clip, idx: idx)
                    }
                    if viewModel.pinnedClips.isEmpty {
                        Text(String(localized: "pin.sidebar.empty"))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.labelSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.pinSidebarPadding)
        .frame(width: DesignTokens.WindowSize.pinSidebarWidth)
        .background(Color.clear)
        .onHover { isHover in
            if isHover {
                viewModel.pinSidebarHoverEnter()
            } else {
                viewModel.pinSidebarHoverExit()
            }
        }
    }

    private var header: some View {
        Text(String(localized: "pin.sidebar.title") + " · \(viewModel.pinnedClips.count)")
            .font(DesignTokens.Typography.pinSidebarHeader)
            .tracking(0.8)  // 0.08em
            .textCase(.uppercase)
            .foregroundStyle(DesignTokens.Colors.pinSidebarHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.pinRowPaddingHorz)
            .padding(.top, DesignTokens.Spacing.pinSidebarHeaderPadTop)
            .padding(.bottom, DesignTokens.Spacing.pinSidebarHeaderPadBottom)
    }

    private func pinItem(clip: Clip, idx: Int) -> some View {
        let isSelected = viewModel.focusZone == .pin && viewModel.pinSelectedIdx == idx
        return HStack(spacing: DesignTokens.Spacing.pinSidebarItemGap) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.accent)
                .rotationEffect(.degrees(45))
            Text(firstLine(clip.body ?? ""))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.pinSidebarItemPadH)
        .frame(height: DesignTokens.Spacing.pinSidebarItemHeight)
        .background(isSelected ? AnyShapeStyle(LinearGradient(colors: [DesignTokens.Colors.clipRowSelectionTop, DesignTokens.Colors.clipRowSelectionBottom], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.pinSidebarItem, style: .continuous))
    }

    private func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
    }
}
