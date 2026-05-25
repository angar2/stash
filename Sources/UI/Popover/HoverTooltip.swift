// popover 상단 버튼 호버 툴팁 (TASK-079) — `.help()` SwiftUI tooltip 우회 인프라
//
// 배경: popover NSPanel = `nonactivatingPanel` styleMask + `becomesKeyOnlyIfNeeded=true` (TASK-058 fix-2) 정책으로
// 대부분 시간 not-key window 상태. macOS NSToolTip (SwiftUI `.help()` 의 backing) 은 *호스팅 NSWindow 가 key 상태*
// 일 때만 발화 — not-key panel 환경에서 발화 정책 미충족.
//
// 본 정책은 TASK-020 (`NSApp.activate` 회피로 외부 앱 first responder 보존) + TASK-058 fix-2 (첫 클릭 즉시 view
// 액션) 정합이라 되돌릴 수 없음. 따라서 `.help()` 자체로는 본 popover 환경에서 발화 보장 X → SwiftUI `.overlay`
// + `.onHover` 결합한 자체 호버 툴팁 인프라가 필요.
//
// 옵션 비교:
// - A (native NSToolTip + NSViewRepresentable wrap): NSView 단위 `addToolTip(_:owner:userData:)` API 사용.
//   not-key panel 동작이 공식 docs 미명시 영역 — POC 결과 회귀 위험. 폐기.
// - B (채택): SwiftUI `.overlay` + 자체 호버 추적. not-key 제약 무관 (SwiftUI overlay 영역). 시각만 NSToolTip
//   흉내 박으면 사용자 위화감 0. 메모리 [macOS UI 정책 fix 영역 incremental + 통째 갈아엎기 금지] 정합.
// - C (호버 시 panel key 박음): TASK-020 / TASK-058 fix-2 정합 침해. 폐기.

import SwiftUI

/// 호버 진입/이탈 상태 머신. 단위 테스트 가능한 순수 상태 (SwiftUI ViewModifier 분리).
///
/// `enter(delay:)` 호출 후 `delay` 시간 경과 시 `isVisible = true`. 진행 중 `exit()` 호출 시 pending task
/// 취소 + 즉시 `isVisible = false`. 연속 `enter(delay:)` 호출 시 이전 pending 취소 + 신규 task 생성.
@MainActor
@Observable
final class HoverTooltipController {
    private(set) var isVisible: Bool = false
    private var pendingTask: Task<Void, Never>? = nil

    /// 호버 진입 — `delay` 시간 후 `isVisible = true`. 진행 중 pending task 있으면 취소 + 신규 task 생성.
    func enter(delay: TimeInterval) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isVisible = true
        }
    }

    /// 호버 이탈 — pending task 취소 + `isVisible = false` 즉시 반영.
    func exit() {
        pendingTask?.cancel()
        pendingTask = nil
        isVisible = false
    }
}

/// 호버 툴팁 SwiftUI ViewModifier. `.overlay` + `.onHover` 결합 + 시각 렌더링.
///
/// macOS 시스템 NSToolTip 시각 흉내 (반투명 배경 + 옅은 테두리 + 작은 폰트 + 라운드 모서리). 버튼 아래
/// `tooltipOffsetY` 만큼 떨어진 위치에 표시. 툴팁 자체는 hover/click 가로채지 X (`.allowsHitTesting(false)`).
///
/// alignment 파라미터로 popover 가장자리 회피. 기본 `.bottomTrailing` — popover 우측 끝 버튼이 호출처일 때
/// 툴팁이 좌측으로 펼쳐져 popover content view 안에 박힘 보장. 좌측 끝 버튼은 `.bottomLeading` 으로 호출처가
/// override.
struct HoverTooltipModifier: ViewModifier {
    let text: String
    let delay: TimeInterval
    let alignment: Alignment

    @State private var controller = HoverTooltipController()

    func body(content: Content) -> some View {
        content
            .onHover { isHover in
                if isHover {
                    controller.enter(delay: delay)
                } else {
                    controller.exit()
                }
            }
            .overlay(alignment: alignment) {
                if controller.isVisible {
                    tooltipView
                        .fixedSize()
                        .offset(y: DesignTokens.Spacing.tooltipOffsetY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: DesignTokens.Animation.tooltipFade), value: controller.isVisible)
    }

    private var tooltipView: some View {
        Text(text)
            .font(DesignTokens.Typography.tooltip)
            .foregroundStyle(DesignTokens.Colors.tooltipLabel)
            .lineLimit(1)
            .padding(.horizontal, DesignTokens.Spacing.tooltipPaddingH)
            .padding(.vertical, DesignTokens.Spacing.tooltipPaddingV)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.tooltip, style: .continuous)
                    .fill(DesignTokens.Colors.tooltipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.tooltip, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.tooltipBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    /// popover 상단 버튼 호버 툴팁 (TASK-079) — `.help()` 우회.
    ///
    /// 호버 진입 후 `delay` 시간 (default `Constants.hoverTooltipDelaySeconds` = 0.8s) 경과 시 표시.
    /// 호버 이탈 시 즉시 사라짐 (잔존 X).
    ///
    /// `alignment` — 툴팁 펼침 방향 결정 (default `.topTrailing`).
    /// - vertical `.top` — overlay top = content top + `tooltipOffsetY` (= 버튼 height 16 + gap 6 = 22) → 버튼 *완전 아래* 비켜 박음 (버튼 영역 안 가림).
    /// - horizontal `.trailing` — overlay 가 좌측으로 펼쳐짐 (popover 우측 끝 버튼이 호출처일 때 popover 가장자리 안 박힘).
    /// 좌측 끝 호출처는 `.topLeading` override.
    func hoverTooltip(
        _ text: String,
        delay: TimeInterval = Constants.hoverTooltipDelaySeconds,
        alignment: Alignment = .topTrailing
    ) -> some View {
        modifier(HoverTooltipModifier(text: text, delay: delay, alignment: alignment))
    }
}
