// Onboarding 윈도우 (3단계 모달). TASK-070 — 시스템 색상 모드 분기 제거 + 진행 도트 시각 (활성 가로 늘림 X / 색상만 accent) + 시스템 표준 NSWindow 패턴 (titled + transparent titlebar) 정합.
// 진행 도트 + WelcomeStep / PermissionStep / TutorialStep 분기 + OnboardingNSWindow (ESC 차단 NSWindow subclass)
import SwiftUI
import AppKit

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
        .frame(width: DesignTokens.WindowSize.onboardingWidth, height: 380, alignment: .top)
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
            .frame(width: 6, height: 6)
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

// TASK-070 — ESC 차단 + canBecomeKey 보장 NSWindow subclass. 종료 경로 = 완료 버튼 only 정책 정합.
final class OnboardingNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// ESC 키 default action (cancelOperation) no-op override — 종료 경로는 완료 버튼만.
    override func cancelOperation(_ sender: Any?) {
        // 의도적 무반응 — TASK-070 종료 정책 (X 버튼 + ESC 차단 / 완료 버튼만 종료).
    }
}
