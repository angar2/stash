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
        // TASK-033 — 환경설정 윈도우 내부 토스트 시스템 (popover 토스트와 별개). Login Item 실패 / 권한 변동 / 단축키 modifier 검증 / 충돌 검사 토스트 발행 채널.
        .overlay(alignment: .top) {
            SettingsToastBar(queue: viewModel.settingsToast)
        }
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

    // MARK: - Settings toast (TASK-033)
    private struct SettingsToastBar: View {
        @Bindable var queue: ToastQueue

        var body: some View {
            VStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                ForEach(queue.stack) { item in
                    ToastView(item: item, onDismiss: { queue.dismiss(id: item.id) })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.top, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(!queue.stack.isEmpty)
            .animation(.easeInOut(duration: 0.2), value: queue.stack.count)
        }
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
            // TASK-033 — 시각 활성화 영역 (frame + padding + RoundedRectangle background) 전체를 클릭 hit testing 영역으로. 기본 Button hit testing 은 VStack 컨텐츠 (아이콘+텍스트) 만 잡아 padding 영역 클릭 무반응이던 결함 fix.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
