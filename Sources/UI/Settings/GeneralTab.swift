// 설정 일반 탭 — Login Item 토글 / 바로 붙여넣기 토글 + 권한×스위치 매트릭스 / 히스토리 한도 정보 라인 (TASK-033 정합)
// UX-UI §4-2 갱신 정합 — 기존 *Paste 동작 모드 라디오 2-옵션* 폐기 → 단일 토글 + 권한 상태 라인 + 시스템 설정 링크
import SwiftUI

struct GeneralTab: View {
    @Bindable var viewModel: SettingsViewModel
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 Toggle ON 배경 / 강조 텍스트 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue

    /// TASK-073 — 언어 변경 시 GeneralTab 본문 즉시 재평가 (라디오 선택 표시 정합 + 모든 i18n 키 lookup 새 언어).
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        let _ = accentColorModeRaw  // SwiftUI 의존성 등록
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 0) {
            settingsCard {
                loginItemRow
                autoPasteRow
                historyLimitRow
                languageRow
            }
        }
    }

    // MARK: - Rows

    private var loginItemRow: some View {
        settingsRow(
            label: L10n("settings.general.loginItem"),
            hint: nil,
            showDivider: true
        ) {
            customSettingsToggle(
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
            label: L10n("settings.general.paste.label"),
            hint: L10n("settings.general.paste.hint"),
            showDivider: true
        ) {
            VStack(alignment: .leading, spacing: 8) {
                customSettingsToggle(
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
            // TASK-065 — 링크 hover 시 텍스트 opacity 증가 (시각 피드백). 링크 버튼은 underline + 색상 변화만으로 충분.
            _PermissionLink(action: { viewModel.openSystemSettingsForAccessibility() })
            Text(granted
                 ? L10n("settings.general.paste.permission.granted.suffix")
                 : L10n("settings.general.paste.permission.denied.suffix"))
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
        }
    }

    /// TASK-033 — 히스토리 한도 정보 라인. 사용자 변경 X (정보 노출만). 값은 `Constants.maxUnpinnedClips` 동적 바인딩.
    private var historyLimitRow: some View {
        settingsRow(
            label: L10n("settings.general.historyLimit"),
            hint: nil,
            showDivider: true
        ) {
            Text("\(viewModel.maxUnpinnedClips)\(L10n("settings.general.historyLimit.unit"))")
                .font(DesignTokens.Typography.settingsBody)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
        }
    }

    /// TASK-073 — 앱 사용자 표시 언어 라디오 (한국어 / 영어). 변경 즉시 popover / 환경설정 / 메뉴바 우클릭 메뉴 새 언어 전환. TASK-053 *콘텐츠 색상* 라디오 패턴 정합.
    private var languageRow: some View {
        settingsRow(
            label: L10n("settings.general.language.label"),
            hint: nil,
            showDivider: false
        ) {
            Picker(
                "",
                selection: Binding(
                    get: { viewModel.appLanguage },
                    set: { viewModel.setAppLanguage($0) }
                )
            ) {
                Text(L10n("settings.general.language.korean"))
                    .tag(AppLanguage.korean)
                Text(L10n("settings.general.language.english"))
                    .tag(AppLanguage.english)
            }
            // TASK-073 Phase 7 — 사용자 피드백 fix: 라디오 → 드롭다운.
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

@MainActor
private struct _PermissionLink: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(L10n("settings.general.paste.permission.linkText"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.accent.opacity(isHovered ? 1.0 : 0.75))
                .underline()
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Shared toggle helpers (TASK-037 fix-refactor — DisplayTab 등 다른 탭 공유 위해 file-level 박음. settingsCard / settingsRow 동일 패턴.)

@MainActor
func customSettingsToggle(isOn: Binding<Bool>, disabled: Bool) -> some View {
    // TASK-065 — hover state 가져야 해서 sub-View struct 로 추출. 외부 호출 시그니처 유지.
    _SettingsCapsuleToggle(isOn: isOn, disabled: disabled)
}

@MainActor
private struct _SettingsCapsuleToggle: View {
    @Binding var isOn: Bool
    let disabled: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            isOn.toggle()
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(settingsToggleFillColor(isOn: isOn, disabled: disabled))
                    .frame(width: 36, height: 22)
                    // TASK-065 — hover 시 트랙 위에 흰색 옅은 overlay (off/on 모두 약간 밝아짐 — macOS NSSwitch hover 패턴 정합).
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(isHovered && !disabled ? 0.14 : 0))
                            .frame(width: 36, height: 22)
                    )
                Circle()
                    .fill(disabled ? Color.white.opacity(0.5) : Color.white)
                    .frame(width: 18, height: 18)
                    // TASK-065 — hover 시 knob 그림자 강화 (clickable 시각 피드백).
                    .shadow(color: Color.black.opacity(isHovered && !disabled ? 0.45 : 0.25), radius: isHovered ? 2.5 : 1, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1.0)
        .onHover { hovering in
            guard !disabled else { return }
            isHovered = hovering
        }
    }
}

@MainActor
func settingsToggleFillColor(isOn: Bool, disabled: Bool) -> Color {
    if disabled {
        return DesignTokens.Colors.toggleOffBg
    }
    return isOn ? DesignTokens.Colors.toggleOnBg : DesignTokens.Colors.toggleOffBg
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
