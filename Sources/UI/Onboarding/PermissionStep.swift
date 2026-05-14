// Onboarding 2단계 — onboarding-toast.jsx OB_Permission L73-142 100% 정합
// 권한 X 대기 = lock 아이콘 회색 / 권한 O = 그린 그라데이션 + ✓
import SwiftUI

struct PermissionStep: View {
    @Bindable var viewModel: OnboardingViewModel

    private var granted: Bool { viewModel.permissionGrantedSnapshot }

    var body: some View {
        VStack(spacing: 0) {
            largeIcon
                .padding(.top, 8)
                .padding(.bottom, 18)

            Text(String(localized: granted ? "onboarding.permission.title.granted" : "onboarding.permission.title.waiting"))
                .font(DesignTokens.Typography.onboardingTitleMid)
                .tracking(-0.27)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .padding(.bottom, 8)

            Text(String(localized: granted ? "onboarding.permission.body.granted" : "onboarding.permission.body.waiting"))
                .font(DesignTokens.Typography.onboardingBody)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.bottom, 24)

            if !granted {
                VStack(spacing: 10) {
                    OnboardingPrimaryButton(String(localized: "onboarding.permission.openSystemSettings")) {
                        viewModel.openSystemSettingsForAccessibility()
                    }

                    // 수동 "다음으로" 버튼 — polling 자동 감지 안 될 때 안전망
                    Button(action: { viewModel.advanceToTutorial() }) {
                        Text(String(localized: "onboarding.permission.next"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.accent)
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.skipPermissionWithCopyBack() }) {
                        Text(String(localized: "onboarding.permission.skip"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.labelSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 28)
            } else {
                OnboardingPrimaryButton(String(localized: "onboarding.tutorial.complete.alt")) {
                    viewModel.advanceToTutorial()
                }
                .padding(.bottom, 28)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.onboardingPadH)
        .padding(.top, 28)
    }

    @ViewBuilder
    private var largeIcon: some View {
        if granted {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DesignTokens.Colors.toastSuccess, Color(red: 30/255, green: 157/255, blue: 69/255)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: DesignTokens.Colors.toastSuccess.opacity(0.35), radius: 14, y: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(.white)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(DesignTokens.Colors.permissionIconBg)
                    .frame(width: 96, height: 96)
                Image(systemName: "lock.shield")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
        }
    }
}
