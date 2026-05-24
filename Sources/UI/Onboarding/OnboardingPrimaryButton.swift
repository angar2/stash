// Onboarding 공통 primary 버튼 — 그라데이션 단일 톤 (#2D86F5 → #0D6FFF). TASK-070 — 시스템 색상 모드 분기 제거 (온보딩 단계는 환경설정 진입 전 → 사용자가 시스템 색상으로 설정해볼 수 없는 상태 → 분기 무의미).
import SwiftUI

struct OnboardingPrimaryButton: View {
    let label: String
    let horizontalPadding: CGFloat
    let action: () -> Void

    init(_ label: String, horizontalPadding: CGFloat = 24, action: @escaping () -> Void) {
        self.label = label
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DesignTokens.Typography.onboardingButtonText)
                .foregroundStyle(Color.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.primaryButtonStart,
                            DesignTokens.Colors.accent
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
