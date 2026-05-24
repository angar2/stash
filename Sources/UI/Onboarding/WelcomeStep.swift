// Onboarding 1단계 — onboarding-toast.jsx OB_Welcome L51-71 100% 정합
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

            VStack(spacing: 4) {
                Text(String(localized: "onboarding.welcome.subtitle.line1"))
                Text(String(localized: "onboarding.welcome.subtitle.line2"))
            }
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
