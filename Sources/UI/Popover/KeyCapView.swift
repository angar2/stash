// 단축키 키캡 시각 — DesignTokens.Typography.keycap / keycapBg / keycapInset / Radius.keycap 토큰 묶음 view
import SwiftUI

struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.keycap)
            .foregroundStyle(DesignTokens.Colors.keycapFg)
            .tracking(0.18)  // 0.02em ≒ 0.18pt at 9pt
            .frame(minWidth: DesignTokens.WindowSize.keycapMin, minHeight: 14)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                    .fill(DesignTokens.Colors.keycapBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                            .stroke(DesignTokens.Colors.keycapInset, lineWidth: 0.5)
                    )
            )
    }
}
