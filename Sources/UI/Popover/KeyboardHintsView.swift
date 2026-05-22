// 단축키 힌트바 — popover.jsx L165-207 100% 정합 (TASK-033 fix-2 — PopoverShortcutStore 동적 조회로 사용자 변경 단축키 즉시 반영)
import SwiftUI

// PopoverInvocationMode — popover 호출 진입 모드 분기 (popover form 단위 분기).
// .method1 = 메뉴바 클릭 popover form (NSStatusItem 좌클릭, 메뉴바 아이콘 아래 앵커).
// .method2 = 키보드 단축키 진입 popover form (활성 화면 우하단). 트리거 진입점 = ⌘⇧V SPM (Carbon RegisterEventHotKey, Accessibility 권한 무관, default `⌘⇧V`, ShortcutsTab Recorder 변경 가능). 이전 ⌘ double-tap 트리거는 TASK-046 에서 폐기 — 코드 분기/명명은 처음부터 *키보드 단축키 진입 form* 의미라 트리거 변경에도 그대로 유지.
// .method3 = ⌘ hold popover form (TASK-018 Phase 9 v1.0 보류 / 호출 사이트 미연결). 코드 분기는 미래 부활 가능 유지.
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
        // TASK-033 fix-2 — 변경 가능 5종 (copy / paste / deleteOne / deleteAll / pinToggle) 은 PopoverShortcutStore 동적 조회. 사용자가 환경설정 단축키 변경 시 popover 재오픈 또는 view rebuild 시 즉시 반영. ↑/↓ · ⌘↑/⌘↓ · ⌘⇧↑/⌘⇧↓ 는 hardcoded (변경 불가).
        // TASK-024 — ⌘V 행만 `enabled = accessibilityGranted` 분기. 권한 X 시 회색조.
        // TASK-036 — `page` (⌘↑/⌘↓ 페이지 점프) + `jumpEdge` (⌘⇧↑/⌘⇧↓ 양 끝 점프) hint 분리. 학습 흐름: 단독 → 페이지 → 양끝.
        return [
            Hint(id: "move", parts: [.keys(["↑", "↓"])], label: String(localized: "hint.move"), enabled: true),
            Hint(id: "page", parts: [.keys(["⌘↑", "⌘↓"])], label: String(localized: "hint.page"), enabled: true),
            Hint(id: "jumpEdge", parts: [.keys(["⌘⇧↑", "⌘⇧↓"])], label: String(localized: "hint.jumpToEdge"), enabled: true),
            Hint(id: "copy", parts: [.keys([keyDisplay(for: .copy, fallback: "⌘C")])], label: String(localized: "hint.copy"), enabled: true),
            Hint(id: "paste", parts: [.keys([keyDisplay(for: .paste, fallback: "⌘V")])], label: String(localized: "hint.paste"), enabled: accessibilityGranted),
            Hint(id: "del", parts: [.keys([keyDisplay(for: .deleteOne, fallback: "⌘⌫")])], label: String(localized: "hint.delete"), enabled: true),
            Hint(id: "delAll", parts: [.keys([keyDisplay(for: .deleteAll, fallback: "⌥⌘⌫")])], label: String(localized: "hint.deleteAll"), enabled: true),
            Hint(id: "pin", parts: [.keys([keyDisplay(for: .pinToggle, fallback: "⌘P")])], label: String(localized: "hint.pin"), enabled: true)
        ]
    }

    /// TASK-033 fix-2 — PopoverShortcutStore 동적 조회 헬퍼. 미등록 시 fallback (default 단축키 시각 표현) 반환.
    private func keyDisplay(for id: PopoverShortcutID, fallback: String) -> String {
        PopoverShortcutStore.get(id)?.displayText ?? fallback
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
