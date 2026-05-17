// 단축키 힌트바 — popover.jsx L165-207 100% 정합 (방식별 modifier 분기 + 키캡 group + or + label)
import SwiftUI

enum PopoverInvocationMode: Sendable {
    case method1
    case method2
    case method3
}

struct KeyboardHintsView: View {
    let mode: PopoverInvocationMode
    /// TASK-024 — Accessibility 권한 게이트. `false` 시 ⌘V 행만 회색조 표시 (`enabled=false` 분기). ⌘C 행은 권한 무관 항상 활성.
    let accessibilityGranted: Bool

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
        // TASK-024 — ⌘C 복사 hint 신규 (⌘V 왼쪽 위치). ⌘V 행만 `enabled = accessibilityGranted` 분기 — 권한 X 시 회색조.
        switch mode {
        case .method1, .method2:
            return [
                Hint(id: "move", parts: [.keys(["↑", "↓"])], label: String(localized: "hint.move"), enabled: true),
                Hint(id: "copy", parts: [.keys(["⌘C"])], label: String(localized: "hint.copy"), enabled: true),
                Hint(id: "paste", parts: [.keys(["⌘V"])], label: String(localized: "hint.paste"), enabled: accessibilityGranted),
                Hint(id: "del", parts: [.keys(["⌘⌫"])], label: String(localized: "hint.delete"), enabled: true),
                Hint(id: "delAll", parts: [.keys(["⌥⌘⌫"])], label: String(localized: "hint.deleteAll"), enabled: true),
                Hint(id: "pin", parts: [.keys(["P"])], label: String(localized: "hint.pin"), enabled: true)
            ]
        case .method3:
            return [
                Hint(id: "move", parts: [.keys(["↑", "↓"])], label: String(localized: "hint.move"), enabled: true),
                Hint(id: "copy", parts: [.keys(["⌘C"])], label: String(localized: "hint.copy"), enabled: true),
                Hint(id: "paste", parts: [.keys(["⌘V"])], label: String(localized: "hint.paste"), enabled: accessibilityGranted),
                Hint(id: "del", parts: [.keys(["⌘⌫"])], label: String(localized: "hint.delete"), enabled: true),
                Hint(id: "delAll", parts: [.keys(["⌥⌘⌫"])], label: String(localized: "hint.deleteAll"), enabled: true),
                Hint(id: "pin", parts: [.keys(["⌘P"])], label: String(localized: "hint.pin"), enabled: true)
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
                            keyCap(key, enabled: hint.enabled)
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
                .foregroundStyle(hint.enabled ? DesignTokens.Colors.hintLabel : DesignTokens.Colors.hintLabelDisabled)
                .padding(.leading, DesignTokens.Spacing.hintsLabelMarginLeft)
        }
    }

    private func keyCap(_ text: String, enabled: Bool) -> some View {
        Text(text)
            .font(DesignTokens.Typography.keycap)
            .foregroundStyle(enabled ? DesignTokens.Colors.keycapFg : DesignTokens.Colors.keycapFgDisabled)
            .tracking(0.18)  // 0.02em ≒ 0.18pt at 9pt
            .frame(minWidth: DesignTokens.WindowSize.keycapMin, minHeight: 14)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                    .fill(enabled ? DesignTokens.Colors.keycapBg : DesignTokens.Colors.keycapBgDisabled)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                            .stroke(enabled ? DesignTokens.Colors.keycapInset : DesignTokens.Colors.keycapInsetDisabled, lineWidth: 0.5)
                    )
            )
    }

    private struct Hint {
        let id: String
        let parts: [Part]
        let label: String
        /// TASK-024 — 비활성 시 키캡 + 라벨 회색조. ⌘V 권한 게이트 시각화에 사용.
        let enabled: Bool
    }

    private enum Part {
        case keys([String])
        case or
    }
}
