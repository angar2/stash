// Onboarding 2단계 — 권한 대기 / 권한 부여 직후 분기. TASK-070 — 시스템 색상 모드 분기 제거 + auto-advance 제거 (다음 페이지 이동은 ViewModel.advanceToTutorial 사용자 명시 호출만).
// 권한 X 대기 = lock 아이콘 회색 / 권한 O = 그린 그라데이션 + ✓
import SwiftUI

struct PermissionStep: View {
    @Bindable var viewModel: OnboardingViewModel
    /// TASK-073 — 언어 변경 시 body 재평가.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    private var granted: Bool { viewModel.permissionGrantedSnapshot }

    var body: some View {
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 0) {
            largeIcon
                .padding(.top, 8)
                .padding(.bottom, 18)

            Text(L10n(granted ? "onboarding.permission.title.granted" : "onboarding.permission.title.waiting"))
                .font(DesignTokens.Typography.onboardingTitleMid)
                .tracking(-0.27)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .padding(.bottom, 8)

            Text(L10n(granted ? "onboarding.permission.body.granted" : "onboarding.permission.body.waiting"))
                .font(DesignTokens.Typography.onboardingBody)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.bottom, 24)

            if !granted {
                VStack(spacing: 10) {
                    OnboardingPrimaryButton(L10n("onboarding.permission.openSystemSettings")) {
                        viewModel.openSystemSettingsForAccessibility()
                    }
                    .accessibilityIdentifier("onboarding.permission.openSystemSettings")

                    // 수동 "다음으로" 버튼 — polling 자동 감지 안 될 때 안전망
                    Button(action: { viewModel.advanceToTutorial() }) {
                        Text(L10n("onboarding.permission.next"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.permission.next")

                    Button(action: { viewModel.skipPermissionWithCopyBack() }) {
                        Text(L10n("onboarding.permission.skip"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.labelSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.permission.skip")
                }
                .padding(.bottom, 28)
            } else {
                OnboardingPrimaryButton(L10n("onboarding.tutorial.complete.alt")) {
                    viewModel.advanceToTutorial()
                }
                .accessibilityIdentifier("onboarding.permission.advanceGranted")
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
