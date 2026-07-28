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
    /// TASK-073 Phase 7 fix — 언어 변경 시 body 재평가 → L10n() 호출 새 언어 lookup. 부모 view sentinel 만으로는 자식 (본 view) 자동 재평가 X (입력 mode/accessibilityGranted 불변).
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 0) {
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

    /// TASK-050 — 단위 테스트 (`KeyboardHintsViewTests`) 접근을 위해 internal 노출. SwiftUI 외부 호출처 없음 (자체 body 안에서만 사용).
    var hints: [Hint] {
        // TASK-033 fix-2 — 변경 가능 5종 (copy / paste / deleteOne / deleteAll / pinToggle) 은 PopoverShortcutStore 동적 조회. 사용자가 환경설정 단축키 변경 시 popover 재오픈 또는 view rebuild 시 즉시 반영. ↑↓ · ⌘↑↓ · ⌘⇧↑↓ 는 hardcoded (변경 불가).
        // TASK-024 — ⌘V 행만 `enabled = accessibilityGranted` 분기. 권한 X 시 회색조.
        // TASK-050 — 이동 단축키 3 hint (move/page/jumpEdge) → 1 통합 cell. 키캡 안 화살표 2 문자 동시 (↑↓ / ⌘↑↓ / ⌘⇧↑↓) + 키캡 그룹 spacing 분리 (구분자 없음) + 라벨 단일화 "이동". `hint.page` / `hint.jumpToEdge` i18n 키 폐기 (Phase 2 xcstrings 정리).
        // TASK-050 — pin 힌트 순서 paste 다음 / del 앞으로 재배치 (클립 조작 흐름: 행 선택 → 복사/붙여넣기/고정 → 삭제 학습 일관성).
        return [
            Hint(id: "move", parts: [.keys(["↑↓"]), .keys(["⌘↑↓"]), .keys(["⌘⇧↑↓"])], label: L10n("hint.move"), enabled: true),
            Hint(id: "copy", parts: [.keys([keyDisplay(for: .copy, fallback: "⌘C")])], label: L10n("hint.copy"), enabled: true),
            Hint(id: "paste", parts: [.keys([keyDisplay(for: .paste, fallback: "⌘V")])], label: L10n("hint.paste"), enabled: accessibilityGranted),
            // TASK-099 — 다중 선택 토글. 복사/붙여넣기 다음 자리 (선택 → 묶음 실행 학습 흐름).
            Hint(id: "multiSelect", parts: [.keys([keyDisplay(for: .multiSelectToggle, fallback: "⌥C")])], label: L10n("hint.multiSelect"), enabled: true),
            Hint(id: "pin", parts: [.keys([keyDisplay(for: .pinToggle, fallback: "⌘P")])], label: L10n("hint.pin"), enabled: true),
            // TASK-055 — 활성 클립 상세 sub-window toggle. 변경 불가 hardcoded ⌘D (PopoverShortcutStore 미등록).
            Hint(id: "clipDetail", parts: [.keys(["⌘D"])], label: L10n("hint.clipDetail"), enabled: true),
            Hint(id: "del", parts: [.keys([keyDisplay(for: .deleteOne, fallback: "⌘⌫")])], label: L10n("hint.delete"), enabled: true),
            Hint(id: "delAll", parts: [.keys([keyDisplay(for: .deleteAll, fallback: "⌥⌘⌫")])], label: L10n("hint.deleteAll"), enabled: true)
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
                    Text(L10n("hint.or"))
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

    /// TASK-050 — 단위 테스트 접근을 위해 internal 노출.
    struct Hint {
        let id: String
        let parts: [Part]
        let label: String
        /// TASK-024 — 비활성 시 키캡 + 라벨 회색조. ⌘V 권한 게이트 시각화에 사용.
        let enabled: Bool
    }

    /// TASK-050 — 단위 테스트 접근을 위해 internal 노출.
    enum Part {
        case keys([String])
        case or
    }
}
