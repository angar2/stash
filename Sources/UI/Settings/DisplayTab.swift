// 설정 디스플레이 탭 — popover 표시 환경 사용자 제어 (TASK-037 / TASK-052 / TASK-053). 한 번에 보이는 클립 수 슬라이더 + 높이 자동 조정 체크박스 + 단축키 설명 표시 체크박스 + 콘텐츠 색상 라디오.
import SwiftUI

struct DisplayTab: View {
    @Bindable var viewModel: SettingsViewModel
    // TASK-053 — 콘텐츠 색상 모드 변경 시 슬라이더 tint / 라디오 / 본 탭 강조 영역 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue

    var body: some View {
        let _ = accentColorModeRaw  // SwiftUI 의존성 등록
        return VStack(spacing: 0) {
            settingsCard {
                clipsPerPageRow
                autoFitRow
                hintBarVisibleRow
                accentColorModeRow
            }
        }
    }

    // MARK: - Rows

    private var clipsPerPageRow: some View {
        settingsRow(
            label: String(localized: "settings.display.clipsPerPage.label"),
            hint: String(localized: "settings.display.clipsPerPage.hint"),
            showDivider: true
        ) {
            HStack(spacing: 12) {
                // step 박지 X — SwiftUI Slider 에 step 박으면 NSSlider tick marks 자동 표시. Binding set 안 rounded Int 변환으로 정수 clamp.
                Slider(
                    value: Binding(
                        get: { Double(viewModel.clipsPerPage) },
                        set: { viewModel.setClipsPerPage(Int($0.rounded())) }
                    ),
                    in: Double(Constants.clipsPerPageMin)...Double(Constants.clipsPerPageMax)
                )
                .frame(maxWidth: DesignTokens.Spacing.displaySliderMaxWidth)
                // TASK-053 — 앱 강조 색상 추종 (UX-UI §4-3 *콘텐츠 색상* 라디오). `.default` = stash 파랑 / `.system` = macOS 시스템 강조 색상.
                .tint(DesignTokens.Colors.accent)
                Text("\(viewModel.clipsPerPage)")
                    .font(DesignTokens.Typography.settingsBody)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    .frame(minWidth: 24, alignment: .trailing)
            }
        }
    }

    private var autoFitRow: some View {
        settingsRow(
            label: String(localized: "settings.display.autoFit.label"),
            hint: String(localized: "settings.display.autoFit.hint"),
            showDivider: true
        ) {
            customSettingsToggle(
                isOn: Binding(
                    get: { viewModel.autoFitClipListHeight },
                    set: { viewModel.setAutoFitClipListHeight($0) }
                ),
                disabled: false
            )
        }
    }

    /// TASK-052 — 단축키 설명 표시 체크박스. default ON. OFF 시 popover 하단 `KeyboardHintsView` 비표시 + popover height 자동 축소 (`displayLayoutDidChange` notification).
    private var hintBarVisibleRow: some View {
        settingsRow(
            label: String(localized: "settings.display.hintBar.label"),
            hint: String(localized: "settings.display.hintBar.hint"),
            showDivider: true
        ) {
            customSettingsToggle(
                isOn: Binding(
                    get: { viewModel.hintBarVisible },
                    set: { viewModel.setHintBarVisible($0) }
                ),
                disabled: false
            )
        }
    }

    /// TASK-053 — 콘텐츠 색상 라디오. 기본 색상 / 시스템 색상 2 선택지. 변경 즉시 강조 view tree 반영. hint 라인 X (사용자 결정).
    private var accentColorModeRow: some View {
        settingsRow(
            label: String(localized: "settings.display.accentColor.label"),
            showDivider: false
        ) {
            Picker(
                "",
                selection: Binding(
                    get: { viewModel.accentColorMode },
                    set: { viewModel.setAccentColorMode($0) }
                )
            ) {
                Text(String(localized: "settings.display.accentColor.default"))
                    .tag(AccentColorMode.default)
                Text(String(localized: "settings.display.accentColor.system"))
                    .tag(AccentColorMode.system)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }
}
