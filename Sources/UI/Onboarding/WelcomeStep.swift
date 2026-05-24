// Onboarding 1단계 — 환영 페이지. TASK-070 — 부제 2줄 (line1+line2) → 1줄 (단일 키) 정합.
import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            largeAppIcon
                .padding(.top, 8)
                .padding(.bottom, 20)

            Text(String(localized: "onboarding.welcome.title"))
                .font(DesignTokens.Typography.onboardingTitleLarge)
                .tracking(-0.4)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .padding(.bottom, 8)

            Text(String(localized: "onboarding.welcome.subtitle"))
                .font(DesignTokens.Typography.onboardingBody)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            OnboardingPrimaryButton(String(localized: "onboarding.welcome.next"), action: onNext)
                .padding(.bottom, 36)
        }
        .padding(.horizontal, DesignTokens.Spacing.onboardingPadH)
        .padding(.top, 32)
    }

    private var largeAppIcon: some View {
        Image.stashAppIcon
            .resizable()
            .frame(width: 104, height: 104)
    }
}
