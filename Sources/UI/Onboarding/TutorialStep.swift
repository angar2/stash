// Onboarding 3단계 — onboarding-toast.jsx OB_Tutorial L144-202 정합
// 헤더 + 1 카드 (메뉴바 클릭) + 완료 버튼.
// TASK-018 Phase 9 — 방식 3 (⌘ hold) v1.0 보류 / TASK-046 — ⌘ double-tap 트리거 폐기 (방식 2 popover 자체는 유지 — 트리거 = ⌘⇧V SPM). ⌘ double-tap 표기 카드만 삭제. 방식 2 SPM 단축키 안내 카드 신규 + 디자인 정합은 BACKLOG *온보딩 전체 개편* 별도 task 위임.
import SwiftUI

struct TutorialStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 6) {
                Text(String(localized: "onboarding.tutorial.title"))
                    .font(DesignTokens.Typography.onboardingTitleMid)
                    .tracking(-0.27)
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                Text(String(localized: "onboarding.tutorial.subtitle"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
            .padding(.bottom, 22)

            // 1 카드 — 방식 1 (메뉴바 클릭). ⌘ double-tap 표기 카드 삭제 (TASK-046 — 방식 2 트리거가 ⌘⇧V SPM 으로 변경됨에 따라 표기 정합 필요. 카드 신규는 BACKLOG 온보딩 개편 task 위임) / 방식 3 (⌘ hold) v1.0 보류 (TASK-018 Phase 9).
            VStack(spacing: DesignTokens.Spacing.onboardingCardGap) {
                tutorialCard(
                    keys: String(localized: "onboarding.tutorial.method1.keys"),
                    title: String(localized: "onboarding.tutorial.method1.title"),
                    desc:  String(localized: "onboarding.tutorial.method1.detail")
                )
            }
            .padding(.bottom, 22)

            OnboardingPrimaryButton(String(localized: "onboarding.tutorial.complete"), horizontalPadding: 32, action: onComplete)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private func tutorialCard(keys: String, title: String, desc: String) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.onboardingCardInnerGap) {
            // 키캡 박스 (56×36)
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(
                            light: Color.white,
                            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.08)
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
                        )
                )

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
}
