// 클립 상세 sub-window SwiftUI 본문 (TASK-027) — FEATURES §3-8 정합
// panel 외피 — Provider.makeContent 본문 only. 꼭지(말풍선 화살표) 는 `PopoverWindow.makeBubbleMaskImage` 가 NSVisualEffectView.maskImage 로 panel 자체를 말풍선 모양으로 잘라내 외부로 튀어나오게 처리 (TASK-027 fix).
import SwiftUI
import AppKit

/// 클립 상세 sub-window 본문 SwiftUI View. PopoverWindow 가 `PopoverPanel.mount` 로 detail panel 안에 호스팅.
/// - Parameters:
///   - clip: 활성 다중파일 클립. `ClipDetailRegistry.provider(for:)` 매칭한 Provider 로 본문 트리 생성.
///   - onFileTap: 파일 행 클릭 콜백. `NSWorkspace.activateFileViewerSelecting` + popover dismiss 호출자가 처리.
struct ClipDetailPanelView: View {
    let clip: Clip
    let onFileTap: @MainActor (URL) -> Void

    private var provider: (any ClipDetailProvider)? {
        ClipDetailRegistry.provider(for: clip)
    }

    var body: some View {
        // 좌측 contentW(=clipDetailWidth) 영역에 본문 박음. 우측 arrowW(=clipDetailArrowWidth) 영역은 빈 공간 — panel maskImage 가 그 영역을 꼭지 삼각형 모양으로 잘라냄.
        // panel 의 NSVisualEffectView .popover material 이 base blur 처리. SwiftUI body 자체 배경은 투명 (default).
        HStack(spacing: 0) {
            content
                .frame(width: DesignTokens.WindowSize.clipDetailWidth)
                .padding(DesignTokens.Spacing.clipDetailPadding)
            Color.clear
                .frame(width: DesignTokens.Spacing.clipDetailArrowWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if let provider {
            provider.makeContent(for: clip, onFileTap: onFileTap)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Provider 매칭 없음 — 정상 흐름에서는 도달 X (PopoverWindow.showClipDetailPanel 진입 시 차단됨).
            Color.clear
        }
    }
}
