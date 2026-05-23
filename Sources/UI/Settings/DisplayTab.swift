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
                popoverPositionRow
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
                // TASK-065 — SwiftUI Slider → NSSlider wrap (HoverableSlider) 교체. knob 영역에만 hover 시각 효과 (트랙 hover 효과 X). trackFillColor = `DesignTokens.Colors.accent` (AccentColorMode 분기 추종 — 기존 `.tint` 동일).
                // step 박지 X — Binding set 안 rounded Int 변환으로 정수 clamp.
                HoverableSlider(
                    value: Binding(
                        get: { Double(viewModel.clipsPerPage) },
                        set: { viewModel.setClipsPerPage(Int($0.rounded())) }
                    ),
                    range: Double(Constants.clipsPerPageMin)...Double(Constants.clipsPerPageMax),
                    tint: DesignTokens.Colors.accent
                )
                .frame(maxWidth: DesignTokens.Spacing.displaySliderMaxWidth)
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

    /// TASK-052 — 단축키 가이드 표시 토글. default 가이드 표시.
    /// TASK-065 — 라벨/의미 리버스 (*단축키 설명 표시* → *단축키 가이드 숨기기*). 시각 OFF = 가이드 표시 / 시각 ON = 가이드 숨김.
    /// UserDefaults 키 `hintBarVisible` 유지 (default true = 가이드 표시). UI Binding 만 invert — 변수 진실 (`hintBarVisible: true = 표시`) 보존, KeyboardHintsView 등 사용처 코드 변경 X, 마이그레이션 X.
    private var hintBarVisibleRow: some View {
        settingsRow(
            label: String(localized: "settings.display.hintBar.label"),
            hint: String(localized: "settings.display.hintBar.hint"),
            showDivider: true
        ) {
            customSettingsToggle(
                isOn: Binding(
                    get: { !viewModel.hintBarVisible },
                    set: { viewModel.setHintBarVisible(!$0) }
                ),
                disabled: false
            )
        }
    }

    /// TASK-053 — 콘텐츠 색상 라디오. 기본 색상 / 시스템 색상 2 선택지. 변경 즉시 강조 view tree 반영. hint 라인 X (사용자 결정).
    /// TASK-054 — 디스플레이 탭 마지막 → 5번째 *보관함 오픈 위치* 추가 따라 divider 활성.
    private var accentColorModeRow: some View {
        settingsRow(
            label: String(localized: "settings.display.accentColor.label"),
            showDivider: true
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
            // TASK-065 — *기본 색상* 모드에서도 라디오 dot 이 macOS 시스템 강조 색상으로 보이던 leak 버그 fix. SwiftUI 환경 `accentColor` 추종 차단 + `DesignTokens.Colors.accent` (AccentColorMode 분기 토큰) 강제 박음.
            .tint(DesignTokens.Colors.accent)
        }
    }

    /// TASK-054 — 보관함 오픈 위치. 좌측 큰 라벨 *보관함 오픈 위치* 1개 + 우측 control-col 안 sub-row 2개 세로 스택.
    /// sub-row 1 = *기본 오픈 위치* (Picker 5종 anchor, 폭 = displaySliderMaxWidth/2 ≒ control-col 50%).
    /// sub-row 2 = *이전 위치 기억하기* (capsule 토글, default OFF).
    /// 부가설명 라인 X (사용자 결정 — 라벨만으로 명확). HTML 목업 [.temp/054_settings-popover-position-mockup.html] 정합.
    /// TASK-054 fix-2 — `popoverRememberLastPosition` ON 시 *기본 오픈 위치* Picker disabled (영속 좌표 우선이라 anchor 무의미).
    private var popoverPositionRow: some View {
        let anchorDisabled = viewModel.popoverRememberLastPosition
        return settingsRow(
            label: String(localized: "settings.display.popoverPosition.label"),
            showDivider: false  // 마지막 행
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // sub-row 1 — 기본 오픈 위치 (Picker 드롭다운). 이전 위치 기억하기 ON 시 disabled.
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "settings.display.popoverPosition.defaultAnchor"))
                        .font(DesignTokens.Typography.settingsBody)
                        .foregroundStyle(anchorDisabled ? DesignTokens.Colors.labelSecondary : DesignTokens.Colors.labelPrimary)
                    Picker(
                        "",
                        selection: Binding(
                            get: { viewModel.popoverDefaultAnchor },
                            set: { viewModel.setPopoverDefaultAnchor($0) }
                        )
                    ) {
                        ForEach(PopoverAnchor.allCases, id: \.self) { anchor in
                            Text(String(localized: String.LocalizationValue(anchor.localizationKey)))
                                .tag(anchor)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: DesignTokens.Spacing.displaySliderMaxWidth / 2)
                    // TASK-064 — NSPopUpButton 내부 leading inset 보정. control-col 좌측 시작점과 픽셀 정합. 보정값 -20pt = dev 단계 시각 실측 확정 (macOS Sonoma+ SwiftUI Picker `.menu` style 의 NSPopUpButton wrap 시각 내부 inset). SwiftUI 공식 API 미노출 영역이라 매직값 박음 — DesignTokens 토큰 미박음 (단일 사용처).
                    .padding(.leading, -20)
                    .disabled(anchorDisabled)
                }
                // sub-row 2 — 이전 위치 기억하기 (토글)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "settings.display.popoverPosition.rememberLast"))
                        .font(DesignTokens.Typography.settingsBody)
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    customSettingsToggle(
                        isOn: Binding(
                            get: { viewModel.popoverRememberLastPosition },
                            set: { viewModel.setPopoverRememberLastPosition($0) }
                        ),
                        disabled: false
                    )
                }
            }
        }
    }
}
