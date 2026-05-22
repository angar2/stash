// 클립 상세 sub-window SwiftUI 본문 (TASK-027 / TASK-039) — FEATURES §3-8 정합
// panel 외피 — Provider.makeContent 본문 (raw) + (해당 시) 복사 위치 라인 + 메타 footer 통합.
// 꼭지(말풍선 화살표) 는 `PopoverWindow.makeBubbleMaskImage` 가 NSVisualEffectView.maskImage 로 panel 자체를 말풍선 모양으로 잘라내 외부로 튀어나오게 처리 (TASK-027 fix).
// 본문 영역만 ScrollView wrapping + max height 클램프 → 내부 스크롤 (TASK-039). 복사 위치 라인 + 메타 footer 는 ScrollView 밖에 박혀 항상 보임.
import SwiftUI
import AppKit

/// 클립 상세 sub-window 본문 SwiftUI View. PopoverWindow 가 `PopoverPanel.mount` 로 detail panel 안에 호스팅.
/// - Parameters:
///   - clip: 활성 클립 (4 종 ClipType — text · image · single file · multi file). `ClipDetailRegistry.provider(for:)` 매칭한 Provider 로 본문 트리 생성.
///   - onFileTap: 파일 행 클릭 콜백. `NSWorkspace.activateFileViewerSelecting` + popover dismiss 호출자가 처리.
///   - searchQuery: popover 검색바 현재 입력. Provider chain 으로 본문 텍스트 렌더에 전달 — 매칭 구간 시각 강조 (TASK-049 / UX-UI §7-3). default `""` (강조 미적용).
struct ClipDetailPanelView: View {
    let clip: Clip
    let onFileTap: @MainActor (URL) -> Void
    let searchQuery: String
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 상세 sub-window 본문 검색 매칭 하이라이트 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue

    init(clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String = "") {
        self.clip = clip
        self.onFileTap = onFileTap
        self.searchQuery = searchQuery
    }

    private var provider: (any ClipDetailProvider)? {
        ClipDetailRegistry.provider(for: clip)
    }

    /// 복사 위치 라인 표시 정책 — Clip extension 단일 진실 소스 호출 (TASK-039 refactor).
    private var copyLocationState: ClipDetailCopyLocationState? {
        clip.clipDetailCopyLocationState
    }

    /// 본문 ScrollView max height — `clipDetailMaxHeight - clipMetaFooterHeight - 2 × clipDetailPadding (top + bottom) - (locationState 있을 때 clipMetaLocationBlockHeight)`.
    /// ScrollView.padding(clipDetailPadding) 가 균일 적용되어 *컨테이너 height = ScrollView height + 2 × clipDetailPadding*. PopoverWindow 의 totalH 계산과 정합.
    private var contentMaxHeight: CGFloat {
        var h = DesignTokens.WindowSize.clipDetailMaxHeight
            - DesignTokens.Spacing.clipMetaFooterHeight
            - 2 * DesignTokens.Spacing.clipDetailPadding // top + bottom
        if copyLocationState != nil {
            h -= DesignTokens.Spacing.clipMetaLocationBlockHeight
        }
        return max(h, 0)
    }

    var body: some View {
        // 좌측 contentW(=clipDetailWidth) 영역에 본문 박음. 우측 arrowW(=clipDetailArrowWidth) 영역은 빈 공간 — panel maskImage 가 그 영역을 꼭지 삼각형 모양으로 잘라냄.
        // panel 의 NSVisualEffectView .popover material 이 base blur 처리. SwiftUI body 자체 배경은 투명 (default).
        let _ = accentColorModeRaw  // TASK-053 SwiftUI 의존성 등록
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                // 1. 본문 — ScrollView wrapping + max height 클램프 (내부 스크롤). 외부 padding 균일 적용 (상하좌우 clipDetailPadding=12). Provider 본문은 raw content.
                ScrollView(.vertical, showsIndicators: true) {
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: contentMaxHeight)
                .padding(DesignTokens.Spacing.clipDetailPadding)
                // 2. (해당 시) 복사 위치 라인 — ScrollView 밖, 항상 보임. 자체 padding 박힘 (clipMetaPadH).
                if let state = copyLocationState {
                    CopyLocationLine(state: state)
                }
                // 3. 메타 footer — 항상 보임. 자체 padding 박힘 (clipMetaPadH / clipMetaPadV).
                ClipMetaFooterView(clip: clip)
            }
            .frame(width: DesignTokens.WindowSize.clipDetailWidth)
            Color.clear
                .frame(width: DesignTokens.Spacing.clipDetailArrowWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if let provider {
            provider.makeContent(for: clip, onFileTap: onFileTap, searchQuery: searchQuery)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Provider 매칭 없음 — 정상 흐름에서는 도달 X (PopoverWindow.showClipDetailPanel 진입 시 차단됨).
            Color.clear
        }
    }
}
