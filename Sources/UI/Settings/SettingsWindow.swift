// 설정 윈도우 — settings.jsx L444-509 100% 정합
// Liquid Glass 배경 + 트래픽 라이트 + 4 탭 (gear/keyboard/lock/info) + 콘텐츠 영역
import SwiftUI

struct SettingsWindow: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, shortcuts, privacy, about
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .general: return "settings.tab.general"
            case .shortcuts: return "settings.tab.shortcuts"
            case .privacy: return "settings.tab.privacy"
            case .about: return "settings.tab.about"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .shortcuts: return "keyboard"
            case .privacy: return "lock.shield"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().foregroundStyle(DesignTokens.Colors.divider)
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:    GeneralTab(viewModel: viewModel)
                    case .shortcuts:  ShortcutsTab(viewModel: viewModel)
                    case .privacy:    PrivacyTab(viewModel: viewModel)
                    case .about:      AboutTab(viewModel: viewModel)
                    }
                }
                .padding(DesignTokens.Spacing.settingsContentMargin)
            }
            .frame(maxHeight: DesignTokens.WindowSize.settingsContentMaxH)
        }
        .frame(width: DesignTokens.WindowSize.settingsWidth)
        .background(
            ZStack {
                VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                DesignTokens.Colors.settingsBackground
            }
        )
    }

    private var tabBar: some View {
        HStack(spacing: DesignTokens.Spacing.settingsTabGap) {
            Spacer()
            ForEach(SettingsTab.allCases) { tab in
                tabButton(tab: tab)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.settingsTabbarPadH)
        .padding(.top, DesignTokens.Spacing.settingsTabbarPadTop)
        .padding(.bottom, DesignTokens.Spacing.settingsTabbarPadBottom)
        .background(
            ZStack {
                VisualEffectView(material: .titlebar, blendingMode: .behindWindow)
                DesignTokens.Colors.settingsTabbar
            }
        )
    }

    private func tabButton(tab: SettingsTab) -> some View {
        let selected = tab == selectedTab
        return Button(action: { selectedTab = tab }) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(selected ? DesignTokens.Colors.accent : DesignTokens.Colors.settingsTabUnselectedIcon)
                Text(String(localized: String.LocalizationValue(tab.titleKey)))
                    .font(DesignTokens.Typography.settingsTabLabel)
                    .foregroundStyle(selected ? DesignTokens.Colors.accent : DesignTokens.Colors.labelPrimary)
            }
            .frame(width: DesignTokens.Spacing.settingsTabWidth)
            .padding(.horizontal, DesignTokens.Spacing.settingsTabPadHorz)
            .padding(.vertical, DesignTokens.Spacing.settingsTabPadVert)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsTab, style: .continuous)
                            .fill(DesignTokens.Colors.settingsTabSelectedBg)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
