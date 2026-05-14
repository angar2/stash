// Onboarding 윈도우 (3단계 모달 — onboarding-toast.jsx L8-202 100% 정합)
// 진행 도트 + WelcomeStep / PermissionStep / TutorialStep 분기
import SwiftUI

struct OnboardingWindow: View {
    @Bindable var viewModel: OnboardingViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            progressDots
            Group {
                switch viewModel.phase {
                case .welcome:
                    WelcomeStep(onNext: { viewModel.advanceToPermission() })
                case .permission:
                    PermissionStep(viewModel: viewModel)
                case .tutorial:
                    TutorialStep(onComplete: {
                        viewModel.complete()
                        onClose()
                    })
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: viewModel.phase)
        }
        .frame(width: DesignTokens.WindowSize.onboardingWidth)
        .background(
            ZStack {
                VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                DesignTokens.Colors.onboardingBackground
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.onboardingWindow, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.onboardingWindow, style: .continuous))
        .shadow(color: DesignTokens.Shadow.onboardingShadow, radius: DesignTokens.Shadow.onboardingRadius, y: DesignTokens.Shadow.onboardingOffsetY)
    }

    private var progressDots: some View {
        HStack(spacing: DesignTokens.Spacing.onboardingProgressGap) {
            ForEach(1...3, id: \.self) { step in
                dot(for: step)
            }
        }
        .padding(.top, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    private func dot(for step: Int) -> some View {
        let currentStep = viewModel.phaseAsStep
        let isActive = step == currentStep
        let isPast = step < currentStep
        return Capsule()
            .fill(isActive || isPast ? DesignTokens.Colors.accent : DesignTokens.Colors.progressDotInactive)
            .frame(width: isActive ? 18 : 6, height: 6)
            .animation(.easeInOut(duration: 0.2), value: currentStep)
    }
}

// OnboardingViewModel phase → step 매핑 헬퍼
extension OnboardingViewModel {
    var phaseAsStep: Int {
        switch phase {
        case .welcome: return 1
        case .permission: return 2
        case .tutorial: return 3
        }
    }
}
