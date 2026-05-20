// 설정 디스플레이 탭 — popover 표시 환경 사용자 제어 (TASK-037). 한 번에 보이는 클립 수 슬라이더 + 높이 자동 조정 체크박스.
import SwiftUI

struct DisplayTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            settingsCard {
                clipsPerPageRow
                autoFitRow
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
                // 시스템 accent (macOS 설정) 무관 stash brand 파랑 명시. focus 변동 / inactive 시 회색 변동 차단.
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
            showDivider: false
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
}
