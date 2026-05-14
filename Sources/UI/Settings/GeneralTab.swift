// 설정 일반 탭 — settings.jsx S_General L153-180 정합
// Login Item 토글 / Paste 모드 라디오 (외관 행 X — 시스템 자동 추종 / UX-UI §12-4 디자인 우선 정정)
import SwiftUI

struct GeneralTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            settingsCard {
                settingsRow(
                    label: String(localized: "settings.general.loginItem"),
                    hint: String(localized: "settings.general.loginItem.hint"),
                    showDivider: true
                ) {
                    customToggle(isOn: Binding(
                        get: { viewModel.loginItemEnabled },
                        set: { viewModel.toggleLoginItem($0) }
                    ))
                }
                pasteModeRow
            }
        }
    }

    private var pasteModeRow: some View {
        settingsRow(
            label: String(localized: "settings.general.paste.label"),
            hint: viewModel.accessibilityGranted ? nil : String(localized: "settings.general.paste.hint.noPermission"),
            showDivider: false
        ) {
            VStack(alignment: .leading, spacing: 10) {
                radioOption(
                    selected: viewModel.pasteMode == .autoPaste,
                    label: String(localized: "settings.general.paste.auto"),
                    hint: String(localized: "settings.general.paste.auto.hint"),
                    disabled: !viewModel.accessibilityGranted
                ) {
                    if viewModel.accessibilityGranted { viewModel.setPasteMode(.autoPaste) }
                }
                radioOption(
                    selected: viewModel.pasteMode == .copyBack,
                    label: String(localized: "settings.general.paste.copyBack"),
                    hint: nil,
                    disabled: false
                ) {
                    viewModel.setPasteMode(.copyBack)
                }
            }
        }
    }

    private func customToggle(isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue ? DesignTokens.Colors.toggleOnBg : DesignTokens.Colors.toggleOffBg)
                    .frame(width: 36, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
    }

    private func radioOption(selected: Bool, label: String, hint: String?, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? DesignTokens.Colors.accent : Color(light: .white, dark: Color(red: 1, green: 1, blue: 1, opacity: 0.10)))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0, green: 0, blue: 0, opacity: 0.25), lineWidth: 0.5)
                        )
                    if selected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(DesignTokens.Typography.settingsBody)
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    if let hint {
                        Text(hint)
                            .font(DesignTokens.Typography.settingsHint)
                            .foregroundStyle(DesignTokens.Colors.labelSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Shared settings UI helpers
func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        content()
    }
    .background(DesignTokens.Colors.settingsCardBg)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsCard, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsCard, style: .continuous)
            .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
    )
}

func settingsRow<Control: View>(label: String, hint: String? = nil, showDivider: Bool, @ViewBuilder control: () -> Control) -> some View {
    VStack(spacing: 0) {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(DesignTokens.Typography.settingsBody)
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                if let hint {
                    Text(hint)
                        .font(DesignTokens.Typography.settingsHint)
                        .foregroundStyle(DesignTokens.Colors.labelSecondary)
                }
            }
            .frame(width: DesignTokens.Spacing.settingsLabelWidth, alignment: .leading)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.settingsRowPaddingH)
        .padding(.vertical, DesignTokens.Spacing.settingsRowPaddingV)
        if showDivider {
            Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
        }
    }
}
