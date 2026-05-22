// Onboarding 공통 primary 버튼 — 그라데이션 (popover.jsx + onboarding-toast.jsx 정합). TASK-053 — `.system` 모드 시 단색 fill (Color.accentColor 단일 톤 정합).
import SwiftUI

struct OnboardingPrimaryButton: View {
    let label: String
    let horizontalPadding: CGFloat
    let action: () -> Void
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue

    init(_ label: String, horizontalPadding: CGFloat = 24, action: @escaping () -> Void) {
        self.label = label
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    private var isSystemMode: Bool {
        AccentColorMode(rawValue: accentColorModeRaw) == .system
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DesignTokens.Typography.onboardingButtonText)
                .foregroundStyle(Color.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 9)
                .background(backgroundStyle)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if isSystemMode {
            // 시스템 강조 색상 단색 fill — 자동 lighten 회피 (macOS NSButton primary 정합).
            DesignTokens.Colors.accent
        } else {
            // 기본 색상 모드 — 기존 듀얼 그라데이션 유지 (#2D86F5 → #0D6FFF).
            LinearGradient(
                colors: [
                    DesignTokens.Colors.primaryButtonStart,
                    DesignTokens.Colors.accent
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}
