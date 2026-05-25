// 대용량 텍스트 클립 detail sub-window 본문 — NSTextView + NSScrollView lazy glyph layout (TASK-076)
import SwiftUI
import AppKit
import OSLog

/// 텍스트 클립 detail sub-window 본문 컴포넌트 (TASK-076).
/// SwiftUI `Text(AttributedString)` 은 lazy 아님 — 70000자 같은 큰 본문을 한 번에 layout → 메인 스레드 수십 초~분 블록. (회귀 영역: `TextDetailContentView` legacy.)
/// 본 컴포넌트는 `NSScrollView` (documentView = `NSTextView`) 로 `NSTextStorage` + `NSLayoutManager` 의 lazy glyph layout 활용 → visible rect 글리프만 layout. 큰 본문도 부드러운 스크롤.
/// 검색어 매칭 강조는 `NSAttributedString` attribute (foregroundColor + semibold weight) 로 적용 — `ClipRowView.highlightedAttributedString` SwiftUI 영역 정합 (UX-UI §7-3 / TASK-049).
/// `isSelectable=true` + `isEditable=false` 로 SwiftUI `.textSelection(.enabled)` 동등.
struct ScrollableTextView: NSViewRepresentable {
    let body: String
    let searchQuery: String
    /// AccentColorMode 변경 시 body 재평가 → updateNSView → 검색 매칭 색상 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue

    init(body: String, searchQuery: String = "") {
        self.body = body
        self.searchQuery = searchQuery
    }

    func makeNSView(context: Context) -> NSScrollView {
        // NSTextView.scrollableTextView() factory — NSScrollView + NSTextView 정합 sizing (minSize / maxSize / isVerticallyResizable / isHorizontallyResizable / autoresizingMask=.width / textContainer.widthTracksTextView=true / isFlipped) 자동 박음.
        // 직접 NSScrollView() + NSTextView() 박은 기존 경로는 NSTextView frame=.zero 시점에 setAttributedString 호출 → textContainer effective width=0 → 짧은 본문 layout 결과 frame=.zero 잔존 (회귀 — 짧은 텍스트 detail 본문 빈 회색 박스). factory 정합 path 로 갈아끼움.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        configure(textView)

        // 초기 frame width 명시 — SwiftUI layout pass 박히기 전 시점에도 textContainer width 가 0 박히지 X. autoresizingMask=.width (factory default) 가 이후 NSClipView 폭 추적해서 자동 갱신.
        let initialWidth = DesignTokens.WindowSize.clipDetailWidth
            - 2 * DesignTokens.Spacing.clipDetailPadding
        textView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: 0)

        Logger.ui.debug("ScrollableTextView.makeNSView: body length=\(self.body.count) initWidth=\(initialWidth)")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        _ = accentColorModeRaw  // SwiftUI 의존성 등록 — accent / language 변경 시 attribute 재적용
        textView.textStorage?.setAttributedString(makeAttributedString())
        // SwiftUI frame 박힌 후 호출 시점 — layout 재발화 보장 (짧은 텍스트 0 폭 wrap 잔존 회피)
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        textView.needsDisplay = true
    }

    /// SwiftUI 의 frame(maxHeight:) 가 자식 *ideal size* 인식해 클램프 동작하도록 ideal height 제공 (TASK-076 Phase 4 fix).
    /// 없으면 NSScrollView intrinsicContentSize=noIntrinsic 이라 SwiftUI 가 maxHeight 까지 grow → 짧은 본문에도 본문 영역 maxHeight 채움 (빈 공백 회귀).
    /// `NSLayoutManager.usedRect` 단독 측정 — `TextClipDetailProvider.preferredHeight` 와 동일 path → PopoverWindow detailH (= contentH + extraH) 정합.
    ///
    /// *중요*: 반환 height 는 `min(ideal, proposal.height)` 로 클램프 — SwiftUI `frame(maxHeight:)` 가 propose 로 maxHeight 박은 후 호출하므로, ideal 무한대 반환 시 SwiftUI 가 ideal 그대로 frame 박아 maxHeight 클램프 효과 깨짐 (긴 본문 panel 전체 채움 + 스크롤 X 회귀). proposal 따라 클램프 의무.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? (DesignTokens.WindowSize.clipDetailWidth - 2 * DesignTokens.Spacing.clipDetailPadding)
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let storage = NSTextStorage(string: body, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        let idealHeight = ceil(layoutManager.usedRect(for: container).height)
        let proposedHeight = proposal.height ?? CGFloat.greatestFiniteMagnitude
        return CGSize(width: width, height: min(idealHeight, proposedHeight))
    }

    /// NSTextView 설정 — selectable 본문 / 시스템 텍스트 변환 차단 / 배경 투명 (NSVisualEffectView material 보존).
    private func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.usesFindBar = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isRichText = false
        textView.allowsUndo = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
    }

    /// 본문 NSAttributedString 생성 — base font/color + 검색 매칭 구간 강조.
    /// 매칭 정책: 빈 query → 강조 미적용 / 다중 매칭 / case-insensitive (`ClipRowView.highlightedAttributedString` 정합).
    private func makeAttributedString() -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textColor = NSColor(DesignTokens.Colors.labelPrimary)

        let attr = NSMutableAttributedString(string: body)
        let fullRange = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.font, value: baseFont, range: fullRange)
        attr.addAttribute(.foregroundColor, value: textColor, range: fullRange)

        guard !searchQuery.isEmpty else { return attr }

        let semiBoldFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let matchColor = NSColor(DesignTokens.Colors.searchMatchForeground)
        let nsBody = body as NSString
        var searchRange = NSRange(location: 0, length: nsBody.length)
        while searchRange.location < nsBody.length {
            let range = nsBody.range(of: searchQuery, options: .caseInsensitive, range: searchRange)
            if range.location == NSNotFound { break }
            attr.addAttribute(.font, value: semiBoldFont, range: range)
            attr.addAttribute(.foregroundColor, value: matchColor, range: range)
            searchRange.location = range.location + range.length
            searchRange.length = nsBody.length - searchRange.location
        }
        return attr
    }
}
