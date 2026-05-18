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

// MARK: - Provider protocol

/// 클립 상세 sub-window 본문 공급자. `canProvide` 매칭 시 `makeContent` 가 SwiftUI 본문 트리 반환 + `preferredHeight` 가 panel size 결정.
/// AnyView return — protocol existential + ViewBuilder `some View` 호환 단순화 (API-SPEC §11-2 / *AnyView type erasure* 참조).
/// Sendable 부합 — Registry static let 저장 + Swift 6 strict concurrency 정합. makeContent / onFileTap 은 UI 영역이라 @MainActor 한정.
protocol ClipDetailProvider: Sendable {
    func canProvide(for clip: Clip) -> Bool
    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void) -> AnyView
    func preferredHeight(for clip: Clip) -> CGFloat
}

// MARK: - Registry

/// 정적 등록 Provider 배열 + 매칭 lookup. 본 v1.0 에서는 `MultiFileClipDetailProvider` 하나만 등록.
/// 향후 ClipType 확장 시 Provider 구현 1개 + `providers` 배열 1줄 추가로 끝.
enum ClipDetailRegistry {
    static let providers: [any ClipDetailProvider] = [
        MultiFileClipDetailProvider()
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

    @MainActor func makeContent(for clip: Clip, onFileTap: @escaping @MainActor (URL) -> Void) -> AnyView {
        AnyView(MultiFileDetailContentView(entries: clip.fileEntries ?? [], onFileTap: onFileTap))
    }

    func preferredHeight(for clip: Clip) -> CGFloat {
        let count = clip.fileEntries?.count ?? 0
        let raw = CGFloat(count) * DesignTokens.Spacing.clipDetailRowHeight
            + 2 * DesignTokens.Spacing.clipDetailPadding
        return min(raw, DesignTokens.WindowSize.clipDetailMaxHeight)
    }
}

// MARK: - 다중파일 본문 SwiftUI

/// 다중파일 상세 sub-window 본문 — 파일명 목록 ScrollView. 각 행 클릭 → `originalPath ?? filePath` URL 로 `onFileTap` 발화.
/// 헤더·타이틀·카운트 표시 X (사용자 *파일명 목록만* 요구 정합 — FEATURES §3-8 *범위 + 본문 형태* 참조).
private struct MultiFileDetailContentView: View {
    let entries: [ClipFileEntry]
    let onFileTap: @MainActor (URL) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    fileRow(entry)
                }
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
            Text(displayName)
                .font(DesignTokens.Typography.clipBody)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.clipDetailRowPadH)
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
