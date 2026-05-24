// Onboarding 3단계 — 호출 모델 안내. TASK-070 — 카드 1개 → 카드 2개 (방식 1 메뉴바 아이콘 클릭 + 방식 2 ⇧⌘V 단축키). 카드 1 keycap = 메뉴바 아이콘 Image + 라벨 세로 배치 / 카드 2 = 기존 키캡 모노 텍스트.
import SwiftUI

struct TutorialStep: View {
    let onComplete: () -> Void
    /// TASK-073 — 언어 변경 시 body 재평가.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 6) {
                Text(L10n("onboarding.tutorial.title"))
                    .font(DesignTokens.Typography.onboardingTitleMid)
                    .tracking(-0.27)
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                HStack(spacing: 0) {
                    Text(L10n("onboarding.tutorial.subtitle.prefix"))
                    Text(L10n("onboarding.tutorial.subtitle.code"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(
                                    light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
                                    dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.08)
                                ))
                        )
                    Text(L10n("onboarding.tutorial.subtitle.suffix"))
                }
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
            .padding(.bottom, 22)

            // 2 카드 — 방식 1 (메뉴바 아이콘 클릭) + 방식 2 (⇧⌘V SPM 단축키)
            VStack(spacing: DesignTokens.Spacing.onboardingCardGap) {
                tutorialCard(
                    icon:  Image("MenuBarIcon"),
                    keys:  L10n("onboarding.tutorial.method1.keys"),
                    title: L10n("onboarding.tutorial.method1.title"),
                    desc:  L10n("onboarding.tutorial.method1.detail")
                )
                tutorialCard(
                    icon:  nil,
                    keys:  L10n("onboarding.tutorial.method2.keys"),
                    title: L10n("onboarding.tutorial.method2.title"),
                    desc:  L10n("onboarding.tutorial.method2.detail")
                )
            }
            .padding(.bottom, 22)

            OnboardingPrimaryButton(L10n("onboarding.tutorial.complete"), horizontalPadding: 32, action: onComplete)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private func tutorialCard(icon: Image?, keys: String, title: String, desc: String) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.onboardingCardInnerGap) {
            keycap(icon: icon, keys: keys)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.onboardingCardTitle)
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                Text(desc)
                    .font(DesignTokens.Typography.onboardingCardDesc)
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.onboardingCardPadV)
        .padding(.horizontal, DesignTokens.Spacing.onboardingCardPadH)
        .background(
            Color(
                light: Color(red: 0, green: 0, blue: 0, opacity: 0.03),
                dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.04)
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.onboardingCard, style: .continuous)
                .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.onboardingCard, style: .continuous))
    }

    @ViewBuilder
    private func keycap(icon: Image?, keys: String) -> some View {
        if let icon = icon {
            // 메뉴바 아이콘 + 라벨 세로 배치 (방식 1)
            VStack(spacing: 2) {
                icon
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                Text(keys)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
            }
            .frame(width: 64, height: 36)
            .background(keycapBackground)
        } else {
            // 키캡 모노 텍스트 (방식 2 — ⇧⌘V)
            Text(keys)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 36)
                .background(keycapBackground)
        }
    }

    private var keycapBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(
                light: Color.white,
                dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.08)
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
            )
    }
}
