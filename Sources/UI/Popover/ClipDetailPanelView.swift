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
///   - direction: TASK-055 — sub-window 진입 방향. `.left` (default) 시 본문 좌측 + 꼭지 우측 / `.right` 시 본문 우측 + 꼭지 좌측. `makeBubbleMaskImage` 의 mask flip 과 정합.
struct ClipDetailPanelView: View {
    let clip: Clip
    let onFileTap: @MainActor (URL) -> Void
    let searchQuery: String
    let direction: ClipDetailDirection
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 상세 sub-window 본문 검색 매칭 하이라이트 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue

    init(clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String = "", direction: ClipDetailDirection = .left) {
        self.clip = clip
        self.onFileTap = onFileTap
        self.searchQuery = searchQuery
        self.direction = direction
    }

    private var provider: (any ClipDetailProvider)? {
        ClipDetailRegistry.provider(for: clip)
    }

    /// 복사 위치 라인 표시 정책 — Clip extension 단일 진실 소스 호출 (TASK-039 refactor).
    private var copyLocationState: ClipDetailCopyLocationState? {
        clip.clipDetailCopyLocationState
    }

    /// TASK-076 — 텍스트 클립은 `ScrollableTextView` 가 자체 NSScrollView 동반 (NSTextView lazy glyph layout). 외부 SwiftUI ScrollView wrapping bypass 가드 — 중첩 시 스크롤바 2 개 + SwiftUI ScrollView 가 contentSize 전체 측정 트리거로 lazy 효과 무력화.
    private var isTextClip: Bool {
        clip.type == .text && (clip.body?.isEmpty == false)
    }

    /// 본문 ScrollView max height — `clipDetailMaxHeight - clipMetaFooterHeight - 2 × clipDetailPadding (top + bottom) - (메타 라인 있을 때 clipMetaLocationBlockHeight)`.
    /// 메타 라인 = `copyLocationState != nil` (파일/이미지 — 복사 위치) 또는 `isTextClip` (텍스트 — 글자수 / TASK-076 Phase 4). 동일 블록 height 사용 (시각 폼 정합).
    /// ScrollView.padding(clipDetailPadding) 가 균일 적용되어 *컨테이너 height = ScrollView height + 2 × clipDetailPadding*. PopoverWindow 의 totalH 계산과 정합.
    private var contentMaxHeight: CGFloat {
        var h = DesignTokens.WindowSize.clipDetailMaxHeight
            - DesignTokens.Spacing.clipMetaFooterHeight
            - 2 * DesignTokens.Spacing.clipDetailPadding // top + bottom
        // TASK-076 Phase 4 fix — Clip extension 단일 진실 소스 호출 (PopoverWindow extraH 계산과 정합)
        if clip.hasClipDetailMetaLine {
            h -= DesignTokens.Spacing.clipMetaLocationBlockHeight
        }
        return max(h, 0)
    }

    var body: some View {
        // TASK-055 — 본문/꼭지 좌우 분기. `.left` (default) 본문 좌측 + 꼭지 우측 / `.right` 본문 우측 + 꼭지 좌측. `makeBubbleMaskImage` 의 mask flip 과 정합.
        // panel 의 NSVisualEffectView .popover material 이 base blur 처리. SwiftUI body 자체 배경은 투명 (default).
        let _ = accentColorModeRaw  // TASK-053 SwiftUI 의존성 등록
        return HStack(spacing: 0) {
            if direction == .right {
                // 우측 fallback — 꼭지 공간 좌측 확보.
                Color.clear
                    .frame(width: DesignTokens.Spacing.clipDetailArrowWidth)
            }
            VStack(spacing: 0) {
                // 1. 본문 — 텍스트 클립은 ScrollableTextView 자체 NSScrollView (TASK-076) 라 외부 SwiftUI ScrollView bypass. 그 외 (이미지 / 단일파일 / 다중파일) 는 기존 SwiftUI ScrollView wrapping + max height 클램프. 외부 padding 균일 적용 (상하좌우 clipDetailPadding=12).
                if isTextClip {
                    content
                        .frame(maxWidth: .infinity, maxHeight: contentMaxHeight)
                        .padding(DesignTokens.Spacing.clipDetailPadding)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        content
                    }
                    .frame(maxWidth: .infinity, maxHeight: contentMaxHeight)
                    .padding(DesignTokens.Spacing.clipDetailPadding)
                }
                // 2. 메타 라인 — ScrollView 밖, 항상 보임. 자체 padding 박힘 (clipMetaPadH). 텍스트 클립 (TASK-076 Phase 4) = 글자수 라인 / 파일·이미지 = 복사 위치 라인 (배타).
                if isTextClip {
                    CharacterCountLine(count: clip.body?.count ?? 0)
                } else if let state = copyLocationState {
                    CopyLocationLine(state: state)
                }
                // 3. 메타 footer — 항상 보임. 자체 padding 박힘 (clipMetaPadH / clipMetaPadV).
                ClipMetaFooterView(clip: clip)
            }
            .frame(width: DesignTokens.WindowSize.clipDetailWidth)
            if direction == .left {
                // 좌측 default — 꼭지 공간 우측 확보.
                Color.clear
                    .frame(width: DesignTokens.Spacing.clipDetailArrowWidth)
            }
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
