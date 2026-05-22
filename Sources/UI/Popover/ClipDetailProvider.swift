// 클립 상세 sub-window 본문 공급 protocol + Registry + MultiFile 구현 (TASK-027) — FEATURES §3-8 / API-SPEC §11 정합
// 공통 패턴 — 향후 텍스트·이미지·단일 파일 ClipType detail 확장 시 Provider 구현 1개 + Registry providers 배열 1줄 추가로 끝.
import SwiftUI
import AppKit
import OSLog

// MARK: - Detail request payload

/// `ClipsViewModel.onShowClipDetailChange` 콜백 인자. `PopoverWindow` 가 zone 분기 anchor + rowFrameInPopover 좌표 변환으로 detail panel 위치 결정.
/// Sendable 부합 — @MainActor 콜백 caller/callee 모두 main actor 한정이라 안전.
struct ClipDetailRequest: Sendable {
    let clip: Clip
    let zone: FocusZone
    let rowFrameInPopover: CGRect
}

// MARK: - PreferenceKey — 활성 행 frame 게시

/// 활성 클립 행의 popover 좌표계 frame 을 ScrollView 상위로 전파. `ClipRowView` 의 `isSelected && isFocused` 분기 행만 .zero 외 frame 게시.
/// `HistoryPopover` / `PinSidebarView` 가 ScrollView root 에서 `.coordinateSpace(name: "popover")` + `.onPreferenceChange` 로 수신 → `ClipsViewModel.activeRowFrameInPopover` 갱신.
struct ActiveRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // .zero 게시 (비활성 행) 는 무시 — 활성 행 (.zero 아닌 frame) 만 채택.
        if next != .zero { value = next }
    }
}

/// SwiftUI coordinateSpace 이름 단일 진실 — HistoryPopover / PinSidebarView ScrollView 양쪽 동일 이름 박음. ClipRowView 의 GeometryReader 가 `frame(in: .named(popoverCoordinateSpaceName))` 으로 추출.
let popoverCoordinateSpaceName = "popover"

// MARK: - ViewModifier — popover/PinSidebar root 양쪽 동일 hook 패턴 추출

/// `HistoryPopover` / `PinSidebarView` 의 root view 에 박는 ViewModifier (TASK-027 refactor).
/// (a) popover 좌표계 박음 + (b) ActiveRowFramePreferenceKey 수신 + (c) viewModel.focusZone == activeZone 일 때 `activeRowFrameInPopover` 갱신.
/// 두 view 에서 동일 5 줄 중복이라 단일 ViewModifier 로 통합.
private struct PopoverClipDetailHookModifier: ViewModifier {
    @Bindable var viewModel: ClipsViewModel
    let activeZone: FocusZone

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: popoverCoordinateSpaceName)
            .onPreferenceChange(ActiveRowFramePreferenceKey.self) { frame in
                Task { @MainActor in
                    if frame != .zero && viewModel.focusZone == activeZone {
                        viewModel.activeRowFrameInPopover = frame
                    }
                }
            }
    }
}

extension View {
    /// popover/PinSidebar root 에 박는 hook — TASK-027 detail sub-window 활성 행 frame 게시 통합.
    /// `activeZone == .clip` (HistoryPopover) / `activeZone == .pin` (PinSidebarView) 분기.
    func popoverClipDetailHook(viewModel: ClipsViewModel, activeZone: FocusZone) -> some View {
        modifier(PopoverClipDetailHookModifier(viewModel: viewModel, activeZone: activeZone))
    }
}

// MARK: - 공통 헬퍼 / 복사 위치 컴포넌트 (TASK-039)

/// 다중파일 entries 의 *공통 부모 폴더* 검출 (TASK-039).
/// 모든 entries 가 동일 폴더 안에 있으면 그 폴더 경로 반환, 다르면 nil.
/// macOS Finder ⌘C = UI 제약상 동일 폴더 보장 (99% 케이스). 외부 앱·스크립트로 박은 다른 폴더 케이스 → nil 반환 → UI fallback ("여러 폴더" italic).
func commonParentFolder(_ entries: [ClipFileEntry]) -> String? {
    let folders = Set(entries.compactMap { entry -> String? in
        let path = entry.originalPath.isEmpty ? entry.filePath : entry.originalPath
        return path.isEmpty ? nil : (path as NSString).deletingLastPathComponent
    })
    guard folders.count == 1, let folder = folders.first, !folder.isEmpty else { return nil }
    return folder
}

extension String {
    /// 홈 디렉토리 prefix 를 `~` 로 치환 (`~/Documents/Q1/foo.pdf` 형식). UI 표시용.
    var tildePrefixed: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

/// 복사 위치 라인 상태 (TASK-039). `ClipDetailPanelView` 가 Clip 종류별 컴퓨티드로 분기.
/// `nil` = 라인 자체 숨김 (텍스트 / 메모리 비트맵 이미지).
enum ClipDetailCopyLocationState: Equatable {
    case folder(String)   // 폴더 경로 표시 (`~` prefix 치환됨)
    case multiFolder      // "여러 폴더" italic fallback (다중파일 + 다른 폴더 케이스)
}

// MARK: - Clip extension — sub-window 출처 path 단일 진실 소스 (TASK-039 refactor)

extension Clip {
    /// 파일 클립 (단일 / 이미지 Finder ⌘C) 의 *복사 출처 경로* — `fileOriginalPath` 우선, fallback `filePath`. 둘 다 nil 또는 빈 문자열 시 nil.
    /// 사용처 = SingleFileDetailContentView (파일명 + 클릭 reveal) / ClipDetailCopyLocationState 컴퓨티드 (폴더 경로 추출).
    var fileLocationPath: String? {
        if let original = fileOriginalPath, !original.isEmpty { return original }
        if let path = filePath, !path.isEmpty { return path }
        return nil
    }

    /// 본 클립의 복사 위치 라인 표시 상태 — 단일 진실 소스 (TASK-039 refactor).
    /// `ClipDetailPanelView.copyLocationState` + `PopoverWindow.hasCopyLocation` 모두 본 컴퓨티드 호출 → 분기 정책 중복 제거.
    var clipDetailCopyLocationState: ClipDetailCopyLocationState? {
        if isMultiFile {
            return commonParentFolder(fileEntries ?? []).map { .folder($0) } ?? .multiFolder
        }
        if type == .file && !isMultiFile, let path = fileLocationPath {
            return .folder((path as NSString).deletingLastPathComponent)
        }
        if type == .image, let original = fileOriginalPath, !original.isEmpty {
            return .folder((original as NSString).deletingLastPathComponent)
        }
        return nil // 텍스트 / 메모리 비트맵 이미지
    }
}

/// 복사 위치 라인 (TASK-039) — 단일파일/다중파일/Finder ⌘C 이미지 본문 마지막에 박힘 (ScrollView 밖).
/// 라벨 ("복사 위치") + 폴더 경로 monospace. `.multiFolder` → italic + warn 색상.
/// read-only — tap gesture X (본문 파일 행 클릭이 reveal 책임).
struct CopyLocationLine: View {
    let state: ClipDetailCopyLocationState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "clipDetail.location.label"))
                .font(DesignTokens.Typography.clipMetaLocationLabel)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
            content
                .font(DesignTokens.Typography.clipMetaLocationPath)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.clipMetaPadH)
        .padding(.vertical, DesignTokens.Spacing.clipMetaPadV)
        .frame(height: DesignTokens.Spacing.clipMetaLocationBlockHeight)
        .background(
            // 상단 점선 보더 — 본문 영역과 시각 분리
            DesignTokens.Colors.divider.opacity(0.6)
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .folder(let folder):
            Text(folder.tildePrefixed + "/")
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
        case .multiFolder:
            Text(String(localized: "clipDetail.location.multiFolder"))
                .italic()
                .foregroundStyle(DesignTokens.Colors.toastWarn)
        }
    }
}

// MARK: - Provider protocol

/// 클립 상세 sub-window 본문 공급자. `canProvide` 매칭 시 `makeContent` 가 SwiftUI 본문 트리 반환 + `preferredHeight` 가 panel size 결정.
/// AnyView return — protocol existential + ViewBuilder `some View` 호환 단순화 (API-SPEC §11-2 / *AnyView type erasure* 참조).
/// Sendable 부합 — Registry static let 저장 + Swift 6 strict concurrency 정합. makeContent / onFileTap 은 UI 영역이라 @MainActor 한정.
/// TASK-049 — `searchQuery` 인자 추가. Text/MultiFile/SingleFile Provider 본문 텍스트에 검색어 매칭 시각 강조 적용 (UX-UI §7-3 정합). Image Provider 는 본문 텍스트 X → 인자 무시.
protocol ClipDetailProvider: Sendable {
    func canProvide(for clip: Clip) -> Bool
    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String) -> AnyView
    func preferredHeight(for clip: Clip) -> CGFloat
}

// MARK: - Registry

/// 정적 등록 Provider 배열 + 매칭 lookup. TASK-039 까지 4 Provider 등록.
/// 매칭 우선순위 = 배열 순서 first match. `MultiFile → Image → SingleFile → Text`.
/// 향후 ClipType 확장 시 Provider 구현 1개 + `providers` 배열 1줄 추가로 끝.
enum ClipDetailRegistry {
    static let providers: [any ClipDetailProvider] = [
        MultiFileClipDetailProvider(),
        ImageClipDetailProvider(),
        SingleFileClipDetailProvider(),
        TextClipDetailProvider()
    ]

    /// 첫 매칭 Provider 반환 — `canProvide(for:)` true 인 첫 Provider. 매칭 없음 → nil → sub-window 미진입.
    static func provider(for clip: Clip) -> (any ClipDetailProvider)? {
        providers.first { $0.canProvide(for: clip) }
    }
}

// MARK: - MultiFile 구현체

/// 다중파일 묶음 클립 detail Provider. canProvide = `isMultiFile && fileEntries?.isEmpty == false` (JSON decode 실패 / 빈 entries 자동 차단).
struct MultiFileClipDetailProvider: ClipDetailProvider {
    func canProvide(for clip: Clip) -> Bool {
        clip.isMultiFile && (clip.fileEntries?.isEmpty == false)
    }

    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String) -> AnyView {
        AnyView(MultiFileDetailContentView(entries: clip.fileEntries ?? [], onFileTap: onFileTap, searchQuery: searchQuery))
    }

    /// 본문 자체 height raw 추정 — padding 가산 X (PanelView 가 padding + ScrollView 클램프 책임, TASK-039).
    func preferredHeight(for clip: Clip) -> CGFloat {
        let count = clip.fileEntries?.count ?? 0
        return CGFloat(count) * DesignTokens.Spacing.clipDetailRowHeight
    }
}

// MARK: - 다중파일 본문 SwiftUI

/// 다중파일 상세 sub-window 본문 — 파일명 목록 (raw content, 자체 ScrollView X — TASK-039 정합, PanelView 가 wrapping).
/// 각 행 클릭 → `originalPath ?? filePath` URL 로 `onFileTap` 발화. 복사 위치 라인은 PanelView 가 처리.
/// TASK-049 — 파일명 displayName 의 검색어 매칭 구간을 `ClipRowView.highlightedAttributedString` 으로 시각 강조.
private struct MultiFileDetailContentView: View {
    let entries: [ClipFileEntry]
    let onFileTap: @MainActor (URL) -> Void
    let searchQuery: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                fileRow(entry)
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ entry: ClipFileEntry) -> some View {
        let pathString = entry.originalPath.isEmpty ? entry.filePath : entry.originalPath
        let displayName = (pathString as NSString).lastPathComponent

        HStack(spacing: DesignTokens.Spacing.clipDetailRowInnerGap) {
            Image(systemName: "doc")
                .font(.system(size: DesignTokens.Spacing.clipDetailRowIconSize, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
            Text(ClipRowView.highlightedAttributedString(
                displayName,
                query: searchQuery,
                baseFont: DesignTokens.Typography.clipBody
            ))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: DesignTokens.Spacing.clipDetailRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            let url = URL(fileURLWithPath: pathString)
            Logger.ui.info("ClipDetailPanel: file row tap → \(displayName, privacy: .public)")
            onFileTap(url)
        }
        // TASK-030 — 다중파일 sub-panel 안 파일 행에 손가락 cursor. method3 분기 없음 (sub-panel 자체가 본체 popover 와 별도 윈도우).
        .pointingHandCursor()
    }
}

// MARK: - Text 구현체 (TASK-039)

/// 텍스트 클립 detail Provider. canProvide = `clip.type == .text && body 있음`.
/// 본문 = 전체 본문 표시 (`textSelection(.enabled)`). ScrollView 는 `ClipDetailPanelView` 가 wrapping.
struct TextClipDetailProvider: ClipDetailProvider {
    func canProvide(for clip: Clip) -> Bool {
        clip.type == .text && (clip.body?.isEmpty == false)
    }

    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String) -> AnyView {
        // onFileTap 미사용 — 텍스트는 파일 클릭 동작 없음. PanelView 가 호출자.
        AnyView(TextDetailContentView(body: clip.body ?? "", searchQuery: searchQuery))
    }

    /// 본문 자체 height raw 추정 — `NSAttributedString.boundingRect` 로 *실제 wrap 후 height* 측정 (TASK-039 fix).
    /// 기존 `\n` count 기반 추정은 *긴 한 줄 텍스트의 wrap* 미고려로 panel height 가 *제각각* 표시 미흡 → 정확 측정으로 정합.
    /// padding 가산 X (PanelView 책임).
    func preferredHeight(for clip: Clip) -> CGFloat {
        let body = clip.body ?? ""
        guard !body.isEmpty else { return 0 }
        let contentWidth = DesignTokens.WindowSize.clipDetailWidth
            - 2 * DesignTokens.Spacing.clipDetailPadding
        // .clipBody = Font.system(size: 13, weight: .medium) — NSFont 정합
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: body, attributes: attributes)
        let bounding = attrString.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(bounding.height)
    }
}

/// 텍스트 클립 본문 SwiftUI — raw content (자체 ScrollView·외부 padding 박지 X, PanelView 가 책임).
/// `.textSelection(.enabled)` 로 SwiftUI 시스템 텍스트 선택·복사 활성 (NSTextField 활성화 X — 본체 popover ⌘C/⌘V 동작 영향 X).
/// TASK-049 — 본문 전체 텍스트의 검색어 매칭 구간을 `ClipRowView.highlightedAttributedString` 으로 시각 강조.
private struct TextDetailContentView: View {
    let body_: String
    let searchQuery: String

    init(body: String, searchQuery: String) {
        self.body_ = body
        self.searchQuery = searchQuery
    }

    var body: some View {
        Text(ClipRowView.highlightedAttributedString(
            body_,
            query: searchQuery,
            baseFont: DesignTokens.Typography.clipBody
        ))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

// MARK: - Image 구현체 (TASK-039)

/// 이미지 클립 detail Provider. canProvide = `clip.type == .image && filePath 있음`.
/// 본문 = 전체 이미지 (`aspectRatio(.fit)`). 본문 클릭 → Finder reveal. URL = `fileOriginalPath ?? filePath`.
struct ImageClipDetailProvider: ClipDetailProvider {
    func canProvide(for clip: Clip) -> Bool {
        clip.type == .image && (clip.filePath?.isEmpty == false)
    }

    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String) -> AnyView {
        // searchQuery 미사용 — 이미지 본문은 텍스트 X (UX-UI §7-3 적용 범위 제외).
        _ = searchQuery
        return AnyView(ImageDetailContentView(clip: clip, onTap: onFileTap))
    }

    /// 본문 자체 height raw 추정 — NSImage 로드 후 aspectRatio. 로드 실패 시 16:10 fallback. padding 가산 X (PanelView 책임).
    /// width 식 = `clipDetailWidth - 2 × clipDetailPadding` (실제 Image fit 영역 — PanelView 가 좌우 padding 박음).
    /// NSImage 로드 비용 매 호출 발생 가능 — 200ms debounce 로 활성 1개 한정 → 실측 영향 X.
    func preferredHeight(for clip: Clip) -> CGFloat {
        let path = clip.filePath ?? ""
        let img = path.isEmpty ? nil : NSImage(contentsOfFile: path)
        let ratio: CGFloat
        if let img, img.size.width > 0 {
            ratio = img.size.height / img.size.width
        } else {
            ratio = 10.0 / 16.0 // 16:10 fallback
        }
        let imageW = DesignTokens.WindowSize.clipDetailWidth
            - 2 * DesignTokens.Spacing.clipDetailPadding
        return imageW * ratio
    }
}

/// 이미지 클립 본문 SwiftUI — Image(nsImage:) aspectRatio fit. NSImage 로드 실패 시 LinearGradient fallback.
/// 본문 클릭 → `onTap(URL(fileURLWithPath: fileOriginalPath ?? filePath))` 발화.
private struct ImageDetailContentView: View {
    let clip: Clip
    let onTap: @MainActor (URL) -> Void

    private var loadedImage: NSImage? {
        guard let path = clip.filePath, !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var tapURL: URL {
        let path = clip.fileOriginalPath ?? clip.filePath ?? ""
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                // NSImage 로드 실패 fallback — 16:10 그라데이션 박스
                LinearGradient(
                    colors: [
                        DesignTokens.Colors.accent.opacity(0.6),
                        DesignTokens.Colors.appIconAccent.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            Logger.ui.info("ClipDetailPanel: image tap → Finder reveal")
            onTap(tapURL)
        }
        .pointingHandCursor() // TASK-030 정합
    }
}

// MARK: - SingleFile 구현체 (TASK-039)

/// 단일 파일 (비이미지) 클립 detail Provider. canProvide = `clip.type == .file && !isMultiFile && filePath 있음`.
/// `!isMultiFile` 가드로 MultiFile 우선 매칭 보장.
/// 본문 = SF Symbol (`doc` / `folder` `isDirectory` 분기) + 파일명 1줄. 본문 클릭 → Finder reveal.
struct SingleFileClipDetailProvider: ClipDetailProvider {
    func canProvide(for clip: Clip) -> Bool {
        clip.type == .file && !clip.isMultiFile && (clip.filePath?.isEmpty == false)
    }

    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void, searchQuery: String) -> AnyView {
        AnyView(SingleFileDetailContentView(clip: clip, onTap: onFileTap, searchQuery: searchQuery))
    }

    /// 본문 자체 height raw 추정 = `clipDetailRowHeight` (단일 행 only). padding / 복사 위치 가산 X (PanelView 책임).
    func preferredHeight(for clip: Clip) -> CGFloat {
        DesignTokens.Spacing.clipDetailRowHeight
    }
}

/// 단일 파일 본문 SwiftUI — SF Symbol (`doc` / `folder` `isDirectory` 검사 분기) + 파일명 1줄.
/// 파일명 행 클릭 → `onTap(URL(fileURLWithPath: fileOriginalPath ?? filePath))` 발화.
/// TASK-049 — 파일명 displayName 의 검색어 매칭 구간을 `ClipRowView.highlightedAttributedString` 으로 시각 강조.
private struct SingleFileDetailContentView: View {
    let clip: Clip
    let onTap: @MainActor (URL) -> Void
    let searchQuery: String

    private var pathString: String {
        clip.fileLocationPath ?? ""
    }

    private var displayName: String {
        (pathString as NSString).lastPathComponent
    }

    /// FileManager.fileExists(atPath:isDirectory:) 매 render. 폴더 vs 파일 SF Symbol 분기 위해 필수. 디스크 read 1회 비용 무시 수준.
    private var isDirectory: Bool {
        guard !pathString.isEmpty else { return false }
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: pathString, isDirectory: &isDir)
        return isDir.boolValue
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.clipDetailRowInnerGap) {
            Image(systemName: isDirectory ? "folder" : "doc")
                .font(.system(size: DesignTokens.Spacing.clipDetailRowIconSize, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
            Text(ClipRowView.highlightedAttributedString(
                displayName,
                query: searchQuery,
                baseFont: DesignTokens.Typography.clipBody
            ))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: DesignTokens.Spacing.clipDetailRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            Logger.ui.info("ClipDetailPanel: single file tap → Finder reveal — \(displayName, privacy: .public)")
            onTap(URL(fileURLWithPath: pathString))
        }
        .pointingHandCursor() // TASK-030 정합
    }
}
