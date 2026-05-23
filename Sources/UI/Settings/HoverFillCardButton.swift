// 설정 윈도우 카드형 버튼 hover fill 컴포넌트 (TASK-065 리팩토링)
// `_AddBlockedAppButton` / `_RemoveBlockedAppButton` / `_AboutButton` / `_ResetAllShortcutsButton` 4개 sub-View 통합.
// Button + 카드 background (fill / 선택적 stroke) + hover 시 fill 톤 진해짐 패턴.
import SwiftUI

@MainActor
struct HoverFillCardButton<Label: View>: View {
    let action: () -> Void
    let fill: Color
    let fillHover: Color
    let stroke: Color?
    let cornerRadius: CGFloat
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    init(
        action: @escaping () -> Void,
        fill: Color,
        fillHover: Color,
        stroke: Color? = DesignTokens.Colors.divider,
        cornerRadius: CGFloat = DesignTokens.Radius.settingsButton,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.fill = fill
        self.fillHover = fillHover
        self.stroke = stroke
        self.cornerRadius = cornerRadius
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovered ? fillHover : fill)
                        .overlay(
                            Group {
                                if let stroke {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .stroke(stroke, lineWidth: 0.5)
                                }
                            }
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
