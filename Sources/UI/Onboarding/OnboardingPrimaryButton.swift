// Onboarding 공통 primary 버튼 — 그라데이션 (popover.jsx + onboarding-toast.jsx 정합)
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
                            Color(red: 45/255, green: 134/255, blue: 245/255),
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
