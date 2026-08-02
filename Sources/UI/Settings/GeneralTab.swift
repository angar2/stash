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
                // TASK-102 — 앱의 기동·유지 성격끼리 묶는다. 취향 설정(언어·연결자)은 아래에 남긴다 (UX-UI *자동 업데이트*).
                if viewModel.updateAvailable {
                    autoUpdateRow
                }
                autoPasteRow
                historyLimitRow
                languageRow
                separatorRow
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

    /// TASK-102 — 자동 확인 토글. 저장 버튼 없이 즉시 반영한다(다른 항목과 동일 관례).
    /// 끄면 자동 확인이 멈추므로 popover 배너도 뜨지 않는다. `정보` 탭 직접 확인은 그대로 동작한다.
    ///
    /// 설명 줄은 두지 않는다 (사용자 검수 2026-08-02) — 항목명만으로 뜻이 통해 군더더기였다.
    /// 바로 위 *Mac 켤 때 자동 실행* 도 같은 이유로 설명이 없다.
    private var autoUpdateRow: some View {
        settingsRow(
            label: L10n("settings.general.autoUpdate.label"),
            hint: nil,
            showDivider: true
        ) {
            customSettingsToggle(
                isOn: Binding(
                    get: { viewModel.automaticUpdateChecksEnabled },
                    set: { viewModel.setAutomaticUpdateChecks($0) }
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

    /// TASK-100 — 히스토리 한도 입력 행. 정보 라인(사용자 변경 X)에서 입력란 + 증감 버튼으로 전환.
    private var historyLimitRow: some View {
        settingsRow(
            label: L10n("settings.general.historyLimit"),
            hint: L10n("settings.general.historyLimit.hint"),
            showDivider: true
        ) {
            _HistoryLimitField(viewModel: viewModel)
        }
    }

    /// TASK-073 — 앱 사용자 표시 언어 라디오 (한국어 / 영어). 변경 즉시 popover / 환경설정 / 메뉴바 우클릭 메뉴 새 언어 전환. TASK-053 *콘텐츠 색상* 라디오 패턴 정합.
    private var languageRow: some View {
        settingsRow(
            label: L10n("settings.general.language.label"),
            hint: nil,
            // TASK-099 — 연결자 행이 뒤에 붙어 더 이상 마지막이 아니다 (구분선 필요).
            showDivider: true
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

    /// TASK-099 — 다중 선택 붙여넣기의 *연결자*. 여러 클립을 한 번에 붙여넣을 때 사이에 넣을 문자다.
    /// 카드 마지막 행에 두는 이유 — 붙여넣기 방식의 일부라 일반 탭이 자연스럽고, 사용 빈도는 위 항목들보다 낮다.
    private var separatorRow: some View {
        settingsRow(
            label: L10n("settings.general.separator.label"),
            hint: L10n("settings.general.separator.hint"),
            showDivider: false
        ) {
            _SeparatorField()
        }
    }
}

/// 보관 한도 입력란 (TASK-100). 숫자 입력란 + 입력란 안쪽 우측 증감 버튼.
///
/// 다른 설정 항목과 달리 **입력 즉시 반영하지 않는다** — 확정(Enter · 포커스 이탈) 시점에만 판정한다.
/// 즉시 반영하면 `200` 을 `50` 으로 고치는 도중 `2` · `20` 이 각각 확정으로 취급돼 경고가 연달아 뜨고,
/// 심지어 그 중간값이 한도로 저장된다.
@MainActor
private struct _HistoryLimitField: View {
    @Bindable var viewModel: SettingsViewModel
    /// 입력란에 보이는 문자열. 확정 전까지는 뷰모델 값과 다를 수 있다(그게 이 상태를 따로 두는 이유다).
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldWithStepper
            maxHint
        }
        .onAppear { text = String(viewModel.maxUnpinnedClips) }
        // 숫자만 받는다 — *확정 후 되돌리기* 가 아니라 애초에 안 쳐지게 막는다.
        // 되돌리는 방식은 사용자가 친 글자가 잠시 남았다가 사라져 무엇이 잘못됐는지 알기 어렵다.
        // 빈 문자열은 허용한다(다 지우고 새로 치는 정상 흐름) — 그 상태로 확정하면 직전 값으로 복원된다.
        .onChange(of: text) { _, new in
            let digitsOnly = new.filter { $0.isASCII && $0.isNumber }
            if digitsOnly != new { text = digitsOnly }
        }
        // 증감 버튼 · 확정 결과 · 다른 경로의 변경을 입력란에 되비춘다.
        .onChange(of: viewModel.maxUnpinnedClips) { _, value in
            let rendered = String(value)
            if text != rendered { text = rendered }
        }
        .onChange(of: focused) { _, isFocused in
            guard !isFocused else { return }
            commit()
        }
    }

    /// 입력란 바로 아래 상한 안내. 라벨 쪽 설명이 아니라 **입력란 아래**에 두는 이유 —
    /// 얼마까지 칠 수 있는지는 치는 자리에서 보여야 한다(연결자 입력란의 escape 안내와 같은 규칙).
    /// 숫자를 문구에 박지 않고 상수에서 받는 이유는 상한이 바뀌면 화면이 저절로 따라오게 하려는 것이다.
    private var maxHint: some View {
        Text(String(format: L10n("settings.general.historyLimit.max"), Constants.maxUnpinnedClipsMax))
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.labelSecondary)
    }

    private var fieldWithStepper: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .multilineTextAlignment(.leading)
                .focused($focused)
                .onSubmit { commit() }
                .padding(.leading, 8)
            Spacer(minLength: 4)
            stepper
                .padding(.trailing, 3)
        }
        .frame(width: 92, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DesignTokens.Colors.inputFieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(
                    focused ? DesignTokens.Colors.accent : DesignTokens.Colors.inputFieldBorder,
                    lineWidth: focused ? 1 : 0.5
                )
        )
        .animation(.easeInOut(duration: 0.12), value: focused)
    }

    /// 입력란 *안쪽* 에 두는 상하 버튼. 바깥에 두면 라벨 폭 정렬이 흐트러지고 클릭 대상이 입력란과 멀어진다.
    private var stepper: some View {
        VStack(spacing: 0) {
            _StepButton(systemName: "chevron.up") { step(1) }
            _StepButton(systemName: "chevron.down") { step(-1) }
        }
    }

    private func commit() {
        // 표시값이 그대로면 판정할 것이 없다 — 굳이 조회 · 저장을 돌리지 않는다.
        guard text != String(viewModel.maxUnpinnedClips) else { return }
        let input = text
        Task { text = String(await viewModel.commitMaxUnpinnedClips(input)) }
    }

    private func step(_ delta: Int) {
        // 아직 확정하지 않은 입력이 떠 있으면 그 값을 기준으로 움직인다 (사용자는 보이는 숫자를 기준으로 기대한다).
        let base = Int(text.trimmingCharacters(in: .whitespaces)) ?? viewModel.maxUnpinnedClips
        Task { text = String(await viewModel.stepMaxUnpinnedClips(from: base, delta: delta)) }
    }
}

/// 입력란 안쪽 증감 버튼 한 개. hover 시 배경이 옅게 들어와 눌리는 자리임을 알린다.
///
/// hover 배경에 흰색을 직접 쓰지 않는 이유 — 라이트 모드에서는 입력란 배경도 밝아 흰색 hover 가 통째로 묻힌다
/// (TASK-068 이 popover 액션 버튼에서 같은 회귀를 겪었다). 설정 윈도우용 라이트/다크 대응 토큰을 쓴다.
@MainActor
private struct _StepButton: View {
    let systemName: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .frame(width: 16, height: 9)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isHovered ? DesignTokens.Colors.settingsCardBgHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

/// 연결자 입력란. 저장 버튼 없이 **입력 즉시** UserDefaults 에 반영한다 (다른 설정 항목과 같은 관례).
///
/// 저장하는 값은 사용자가 친 **원문 그대로** 다 — `\n` 두 글자가 입력란에도 그대로 보이고,
/// 실제 개행으로 바뀌는 것은 붙여넣을 때뿐이다(`MultiPasteComposer.resolveSeparator`).
/// 눈에 안 보이는 문자를 입력란에 직접 담으면 사용자가 무엇이 들었는지 확인할 방법이 없어진다.
@MainActor
private struct _SeparatorField: View {
    // 빈 문자열은 *구분 없이 연결* 이라는 유효한 값이라, 미설정일 때만 기본값이 들어간다.
    @AppStorage(Constants.UserDefaultsKeys.multiPasteSeparator) private var separator: String = Constants.multiPasteSeparatorDefault
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $separator)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .focused($focused)
                .padding(.horizontal, 8)
                .frame(width: 120, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DesignTokens.Colors.inputFieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            focused ? DesignTokens.Colors.accent : DesignTokens.Colors.inputFieldBorder,
                            lineWidth: focused ? 1 : 0.5
                        )
                )
                .animation(.easeInOut(duration: 0.12), value: focused)
            escapeHint
        }
    }

    /// 입력란 바로 아래 escape 표기 안내. 라벨 쪽 설명이 아니라 **입력란 아래**에 두는 이유 —
    /// 무엇을 칠 수 있는지는 치는 자리에서 보여야 한다.
    private var escapeHint: some View {
        HStack(spacing: 10) {
            escapePair(code: "\\n", label: L10n("settings.general.separator.escape.newline"))
            escapePair(code: "\\t", label: L10n("settings.general.separator.escape.tab"))
        }
    }

    private func escapePair(code: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(code)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.labelPrimary.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DesignTokens.Colors.keycapBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
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
