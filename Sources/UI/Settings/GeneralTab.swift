// 설정 일반 탭 — Login Item 토글 / 바로 붙여넣기 토글 + 권한×스위치 매트릭스 / 히스토리 한도 정보 라인 (TASK-033 정합)
// UX-UI §4-2 갱신 정합 — 기존 *Paste 동작 모드 라디오 2-옵션* 폐기 → 단일 토글 + 권한 상태 라인 + 시스템 설정 링크
import SwiftUI

struct GeneralTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            settingsCard {
                loginItemRow
                autoPasteRow
                historyLimitRow
            }
        }
    }

    // MARK: - Rows

    private var loginItemRow: some View {
        settingsRow(
            label: String(localized: "settings.general.loginItem"),
            hint: nil,
            showDivider: true
        ) {
            customToggle(
                isOn: Binding(
                    get: { viewModel.loginItemEnabled },
                    set: { viewModel.toggleLoginItem($0) }
                ),
                disabled: false
            )
        }
    }

    private var autoPasteRow: some View {
        settingsRow(
            label: String(localized: "settings.general.paste.label"),
            hint: String(localized: "settings.general.paste.hint"),
            showDivider: true
        ) {
            VStack(alignment: .leading, spacing: 8) {
                customToggle(
                    isOn: Binding(
                        // TASK-033 — 권한 X 시 시각 OFF 강제. UserDefaults 값 (autoPasteEnabled) 은 보존 — 권한 회복 시 사용자 선호 ON 복원.
                        get: { viewModel.accessibilityGranted && viewModel.autoPasteEnabled },
                        set: { viewModel.setAutoPasteEnabled($0) }
                    ),
                    disabled: !viewModel.accessibilityGranted
                )
                permissionStatusLine
            }
        }
    }

    /// TASK-033 — 권한×스위치 매트릭스 우측 상태 라인. SF Symbol 아이콘 (`checkmark.circle.fill` / `xmark.circle.fill`) + 디자인 시스템 색상 (toastSuccess / toastError). *"시스템 접근 권한"* 영역은 파란 링크 → macOS 시스템 설정 Accessibility 화면 직접 열기.
    private var permissionStatusLine: some View {
        let granted = viewModel.accessibilityGranted
        return HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(granted ? DesignTokens.Colors.toastSuccess : DesignTokens.Colors.toastError)
            Button(action: { viewModel.openSystemSettingsForAccessibility() }) {
                Text(String(localized: "settings.general.paste.permission.linkText"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .underline()
            }
            .buttonStyle(.plain)
            Text(granted
                 ? String(localized: "settings.general.paste.permission.granted.suffix")
                 : String(localized: "settings.general.paste.permission.denied.suffix"))
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
        }
    }

    /// TASK-033 — 히스토리 한도 정보 라인. 사용자 변경 X (정보 노출만). 값은 `Constants.maxUnpinnedClips` 동적 바인딩.
    private var historyLimitRow: some View {
        settingsRow(
            label: String(localized: "settings.general.historyLimit"),
            hint: nil,
            showDivider: false
        ) {
            Text("\(viewModel.maxUnpinnedClips)\(String(localized: "settings.general.historyLimit.unit"))")
                .font(DesignTokens.Typography.settingsBody)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
        }
    }

    // MARK: - Helpers

    private func customToggle(isOn: Binding<Bool>, disabled: Bool) -> some View {
        Button(action: {
            guard !disabled else { return }
            isOn.wrappedValue.toggle()
        }) {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(toggleFillColor(isOn: isOn.wrappedValue, disabled: disabled))
                    .frame(width: 36, height: 22)
                Circle()
                    .fill(disabled ? Color.white.opacity(0.5) : Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1.0)
    }

    private func toggleFillColor(isOn: Bool, disabled: Bool) -> Color {
        if disabled {
            return DesignTokens.Colors.toggleOffBg
        }
        return isOn ? DesignTokens.Colors.toggleOnBg : DesignTokens.Colors.toggleOffBg
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
