// 단축키 힌트바 — popover.jsx L165-207 100% 정합 (방식별 modifier 분기 + 키캡 group + or + label)
import SwiftUI

enum PopoverInvocationMode: Sendable {
    case method1
    case method2
    case method3
}

struct KeyboardHintsView: View {
    let mode: PopoverInvocationMode

    var body: some View {
        VStack(spacing: 0) {
            Divider().foregroundStyle(DesignTokens.Colors.divider)
                .padding(.horizontal, DesignTokens.Spacing.popoverPadding)
            FlowLayout(horizontalSpacing: DesignTokens.Spacing.hintsGroupGap, verticalSpacing: DesignTokens.Spacing.xs) {
                ForEach(hints, id: \.id) { hint in
                    hintCell(hint: hint)
                        .fixedSize()
                }
            }
            .padding(.top, DesignTokens.Spacing.hintsBarPaddingTop)
            .padding(.horizontal, DesignTokens.Spacing.hintsBarPaddingHorz)
            .padding(.bottom, DesignTokens.Spacing.hintsBarPaddingBottom)
        }
    }

    private var hints: [Hint] {
        switch mode {
        case .method1, .method3:
            return [
                Hint(id: "move", parts: [.keys(["↑", "↓"]), .or, .keys(["1", "2"])], label: String(localized: "hint.move")),
                Hint(id: "paste", parts: [.keys(["⌘V"])], label: String(localized: "hint.paste")),
                Hint(id: "pop", parts: [.keys(["⌘⇧V"])], label: String(localized: "hint.pop")),
                Hint(id: "del", parts: [.keys(["⌘⌫"])], label: String(localized: "hint.delete")),
                Hint(id: "delAll", parts: [.keys(["⌥⌘⌫"])], label: String(localized: "hint.deleteAll")),
                Hint(id: "pin", parts: [.keys(["P"])], label: String(localized: "hint.pin"))
            ]
        case .method2:
            return [
                Hint(id: "move", parts: [.keys(["⌘↑", "⌘↓"]), .or, .keys(["⌘1", "⌘2"])], label: String(localized: "hint.move")),
                Hint(id: "paste", parts: [.keys(["⌘V"])], label: String(localized: "hint.paste")),
                Hint(id: "pop", parts: [.keys(["⌘⇧V"])], label: String(localized: "hint.pop")),
                Hint(id: "del", parts: [.keys(["⌘⌫"])], label: String(localized: "hint.delete")),
                Hint(id: "delAll", parts: [.keys(["⌥⌘⌫"])], label: String(localized: "hint.deleteAll")),
                Hint(id: "pin", parts: [.keys(["⌘P"])], label: String(localized: "hint.pin"))
            ]
        }
    }

    private func hintCell(hint: Hint) -> some View {
        HStack(spacing: 4) {
            ForEach(hint.parts.indices, id: \.self) { idx in
                switch hint.parts[idx] {
                case .keys(let arr):
                    HStack(spacing: 2) {
                        ForEach(arr, id: \.self) { key in
                            keyCap(key)
                        }
                    }
                case .or:
                    Text("or")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.hintOr)
                }
            }
            Text(hint.label)
                .font(DesignTokens.Typography.hintLabel)
                .foregroundStyle(DesignTokens.Colors.hintLabel)
                .padding(.leading, DesignTokens.Spacing.hintsLabelMarginLeft)
        }
    }

    private func keyCap(_ text: String) -> some View {
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

    private struct Hint {
        let id: String
        let parts: [Part]
        let label: String
    }

    private enum Part {
        case keys([String])
        case or
    }
}
