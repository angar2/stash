// 클립 행 — popover.jsx L74-162 100% 정합
// 좌측 type icon (이미지=NSImage 썸네일 36x32 + 로드 실패 시 그라데이션 fallback / text·file=14px 라인) + 본문 (mono 분기) + 시간 (48px tabular) + Pin/X (선택 시만)
import SwiftUI
import AppKit

struct ClipRowView: View, Equatable {
    let clip: Clip
    let isSelected: Bool
    let isFocused: Bool      // focusZone === "clip" 일 때만 시각 활성
    let isFlashing: Bool
    let mode: PopoverInvocationMode
    /// 시간 라벨 표시 여부 — Pin 사이드바(220 너비) 안에서는 false 박아 본문 truncate 완화 (TASK-019 fix 3차 B8).
    var showTimeLabel: Bool = true
    /// TASK-035 — 검색바 입력 검색어. 비어있지 않으면 본문 매칭 구간을 accent 전경 + semibold 로 강조. Pin 사이드바는 항상 "" 전달 (UX-UI §7-3 적용 범위 제외).
    var searchQuery: String = ""
    let onClick: () -> Void
    let onHover: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    /// TASK-037 fix-15b — Equatable conformance. closure 제외 시각 영향 prop 만 비교.
    /// `.equatable()` modifier 와 함께 사용 → SwiftUI 가 변경된 행만 re-render → 호버 응답 빠름 (selectedIdx 변경 시 다른 행 skip).
    /// Swift 6 concurrency — `nonisolated` 박아 MainActor 격리 외 호출 허용.
    nonisolated static func == (lhs: ClipRowView, rhs: ClipRowView) -> Bool {
        lhs.clip == rhs.clip &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isFocused == rhs.isFocused &&
        lhs.isFlashing == rhs.isFlashing &&
        lhs.mode == rhs.mode &&
        lhs.showTimeLabel == rhs.showTimeLabel &&
        lhs.searchQuery == rhs.searchQuery
    }

    @State private var hovering: Bool = false
    @State private var xHovered: Bool = false
    /// TASK-019 fix 4차 — 핀 아이콘 hover state. 본체 + Pin 사이드바 양쪽 동일 (사용자 결정).
    @State private var pinHovered: Bool = false

    private var visuallySelected: Bool {
        isSelected && isFocused
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.rowInnerGap) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.rowInnerGap) {
                typeIconArea
                content
                Spacer(minLength: 4)
                if showTimeLabel {
                    timeLabel
                }
            }

            actionButton
        }
        .padding(.horizontal, DesignTokens.Spacing.rowPaddingMultiH)
        // TASK-037 — 행 단일 고정 높이 정책. multi-line 가변 padding 제거.
        .frame(height: DesignTokens.Spacing.rowMinHeight)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous))
        // TASK-031 — hit-test 영역 outer 전체로 통합. hover/click/cursor 세 영역 일치 (padding 포함 시각 하이라이트 가장자리까지 클릭 가능).
        // actionButton(핀/X) 영역은 자식 .highPriorityGesture 우선권으로 paste 오작동 차단 (단일 안전망).
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
        .pointingHandCursor(enabled: mode != .method3)
        .onHover { isHover in
            hovering = isHover
            if isHover { onHover() }
        }
        // TASK-037 fix-16 — visuallySelected animation 폐기. 호버 시 highlight 가 120ms fade 거쳐서 *마우스 지나간 후 뒤늦게 색 변경* 인식. 즉시 highlight 박힘.
        // isFlashing animation 은 paste flash 시각 효과라 유지.
        .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: isFlashing)
        // TASK-027 — 활성 행 frame 을 popover coordinateSpace 에 게시. 비활성 행은 .zero (PreferenceKey reduce 가 ignore).
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ActiveRowFramePreferenceKey.self,
                    value: visuallySelected ? proxy.frame(in: .named(popoverCoordinateSpaceName)) : .zero
                )
            }
        )
    }

    // MARK: - Type icon
    @ViewBuilder
    private var typeIconArea: some View {
        switch clip.type {
        case .image:
            // 이미지 썸네일 — 36×32. clip.filePath NSImage 로드 시도 (TASK-023). 실패 시 기존 그라데이션 fallback.
            imageThumbnail
        case .text, .file:
            // 14×14 라인 아이콘 — file 타입은 *다중 묶음 / 폴더 / 파일* sub-분기 (TASK-026 / TASK-016).
            ZStack {
                if clip.type == .file && clip.isMultiFile {
                    // TASK-026 — 다중 파일 묶음. doc.on.doc + 우상단 N 배지.
                    multiFileIconWithBadge
                } else if clip.type == .file {
                    Image(systemName: isFileADirectory ? "folder" : "doc")
                        .font(.system(size: 12, weight: .regular))
                } else {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12, weight: .regular))
                }
            }
            .foregroundStyle(typeIconColor)
            .frame(width: DesignTokens.WindowSize.clipTypeIconArea, alignment: .center)
        }
    }

    /// TASK-026 — 다중 파일 묶음 아이콘 + N 배지. entries decode 실패 시 fallback (`square.stack` 단독).
    /// TASK-042 — 배경 `Circle()` → `Capsule()` 전환 + minWidth 동적 (1자리=12 / 2자리·"99+"=16) + `lineLimit(1)` + `fixedSize` 박아 두 자리 이상 wrap/클리핑 차단. N≥100 은 "99+" 캡 (배지 폭 안정).
    @ViewBuilder
    private var multiFileIconWithBadge: some View {
        let count = clip.fileEntries?.count ?? 0
        ZStack(alignment: .topTrailing) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .regular))
            if let text = Self.badgeText(for: count) {
                let isSingleDigit = text.count <= 1
                Text(text)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 3)
                    .frame(minWidth: isSingleDigit ? 12 : 16, minHeight: 12)
                    .background(
                        Capsule().fill(DesignTokens.Colors.accent)
                    )
                    .offset(x: 6, y: -6)
            }
        }
    }

    /// TASK-042 — 배지에 표시할 텍스트 결정. `nil` 반환 시 배지 미표시.
    /// 분기: count<=0 → nil (0·음수 가드) / 1≤count<100 → "\(count)" / count>=100 → "99+" 캡.
    /// 단위 테스트 대상 — `nonisolated static` 으로 MainActor 격리 외 호출 허용.
    nonisolated static func badgeText(for count: Int) -> String? {
        guard count > 0 else { return nil }
        if count >= 100 { return "99+" }
        return "\(count)"
    }

    /// 이미지 썸네일 — NSImage 로드 성공 시 실제 이미지, 실패 시 그라데이션 박스 (TASK-023).
    @ViewBuilder
    private var imageThumbnail: some View {
        if let path = clip.filePath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: DesignTokens.WindowSize.clipImageThumbW, height: DesignTokens.WindowSize.clipImageThumbH)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 1.5, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            // 로드 실패 fallback — 그라데이션 (popover.jsx L80-89)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.imageGradientStart,
                            DesignTokens.Colors.imageGradientMid,
                            DesignTokens.Colors.imageGradientEnd
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: DesignTokens.WindowSize.clipImageThumbW, height: DesignTokens.WindowSize.clipImageThumbH)
                .shadow(color: Color.black.opacity(0.15), radius: 1.5, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                )
        }
    }

    /// .file 클립의 path가 폴더인지 일반 파일인지 — fileOriginalPath 우선, 없으면 filePath fallback. 둘 다 없으면 false (doc 아이콘).
    private var isFileADirectory: Bool {
        let path = clip.fileOriginalPath ?? clip.filePath
        guard let path else { return false }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    private var typeIconColor: SwiftUI.Color {
        visuallySelected ? DesignTokens.Colors.clipTypeIconSelected : DesignTokens.Colors.clipIconUnselected
    }

    // MARK: - Content
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(displayLines.indices, id: \.self) { idx in
                Text(highlightedLine(idx))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// TASK-035 — 현재 행 idx 의 displayLine 을 검색어 매칭 강조된 AttributedString 으로 반환.
    /// baseFont 분기 (mono vs regular) 는 행 type / body 패턴 따라 결정 (기존 content 분기 정합).
    private func highlightedLine(_ idx: Int) -> AttributedString {
        let baseFont = (clip.type == .text && isMonoBody)
            ? DesignTokens.Typography.clipBodyMono
            : DesignTokens.Typography.clipBody
        return Self.highlightedAttributedString(
            displayLines[idx],
            query: searchQuery,
            baseFont: baseFont
        )
    }

    /// TASK-035 — 순수 함수. source 텍스트에서 query 매칭 구간을 accent 전경 + semibold weight 로 강조한 AttributedString 반환.
    /// 매칭 정책: 대소문자 무시 / 다중 매칭 / 빈 query 면 강조 미적용 (베이스만).
    /// 단위 테스트 대상 — 외부 호출 가능하도록 internal static.
    static func highlightedAttributedString(
        _ source: String,
        query: String,
        baseFont: Font
    ) -> AttributedString {
        var result = AttributedString(source)
        result.font = baseFont
        result.foregroundColor = DesignTokens.Colors.labelPrimary

        guard !query.isEmpty else { return result }

        var cursor = result.startIndex
        while cursor < result.endIndex,
              let range = result[cursor..<result.endIndex].range(of: query, options: .caseInsensitive) {
            result[range].foregroundColor = DesignTokens.Colors.searchMatchForeground
            result[range].font = baseFont.weight(.semibold)
            cursor = range.upperBound
        }

        return result
    }

    /// 이미지 클립 행 라벨 — 4단계 fallback (TASK-023):
    ///  1. `fileOriginalPath` 있으면 → lastPathComponent (Finder 이미지 파일, case C).
    ///  2. `body` 가 http(s) URL 이고 path 유효하면 → URL.lastPathComponent (웹 이미지, 회귀 (g)).
    ///  3. `body` URL 파싱 실패 또는 path 비어있으면 → body 그대로.
    ///  4. `body` 도 nil 이면 → localized "이미지" fallback (스크린샷, case B).
    private var imageDisplayName: String {
        if let originalPath = clip.fileOriginalPath {
            return (originalPath as NSString).lastPathComponent
        }
        if let body = clip.body {
            if let url = URL(string: body),
               let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme),
               !url.lastPathComponent.isEmpty,
               url.lastPathComponent != "/" {
                return url.lastPathComponent
            }
            return body
        }
        return String(localized: "clip.row.image")
    }

    // mono 폰트 분기 — 코드 / URL은 mono. plan은 mono 필드 X. 단순 휴리스틱: 50자 이상이거나 줄바꿈 / 코드 패턴 (^/$/{}/=>/) → mono.
    private var isMonoBody: Bool {
        let body = clip.body ?? ""
        if body.contains("```") || body.contains("=>") || body.contains("function") || body.contains("git ") || body.contains("npm ") {
            return true
        }
        return false
    }

    private var displayLines: [String] {
        switch clip.type {
        case .image:
            return [imageDisplayName]
        case .file:
            // TASK-026 — 다중 파일 묶음 라벨 = `여러 파일` (단순 라벨, N 정보는 배지가 담당).
            // 파일명 리스트 상세는 TASK-027 *클립 상세 미리보기 sub-window* 에서 별도 표시.
            if clip.isMultiFile {
                return [String(localized: "clip.row.multiFile.label")]
            }
            let name = clip.fileOriginalPath.flatMap { ($0 as NSString).lastPathComponent } ?? (clip.body ?? String(localized: "clip.row.file"))
            return [name]
        case .text:
            // TASK-037 — 행 단일 고정 높이 정책. 첫 줄만 노출, 초과는 truncate.
            let body = clip.body ?? ""
            let firstLine = body.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return [firstLine]
        }
    }

    // MARK: - Time label (48px width, tabular-nums)
    private var timeLabel: some View {
        Text(relativeTime)
            .font(DesignTokens.Typography.timeMeta)
            .monospacedDigit()
            .foregroundStyle(DesignTokens.Colors.labelSecondary)
            .frame(width: DesignTokens.WindowSize.timeMetaWidth, alignment: .trailing)
    }

    // 시간 suffix — store.jsx L228-236 100% 정합 (방금 / N분 전 / N시간 전 / 어제 / N일 전)
    private var relativeTime: String {
        let interval = Date().timeIntervalSince(clip.lastUsedAt)
        if interval < 60 { return String(localized: "time.now") }
        if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)\(String(localized: "time.suffix.minutes"))"
        }
        if interval < 86_400 {
            let hours = Int(interval / 3600)
            return "\(hours)\(String(localized: "time.suffix.hours"))"
        }
        if interval < 86_400 * 2 {
            return String(localized: "time.yesterday")
        }
        let days = Int(interval / 86_400)
        return "\(days)\(String(localized: "time.suffix.days"))"
    }

    // MARK: - Action button (Pin or X) — Bug 2 fix v4 (TASK-031 갱신)
    // X·Pin 자식 `.highPriorityGesture` 우선권으로 paste 오작동 차단 (outer hit-test 통합 후 단일 안전망).
    @ViewBuilder
    private var actionButton: some View {
        if clip.isPinned {
            // 핀 표시 — *visuallySelected 무관 항상 표시* (X 아이콘과 차별점). 방식 2는 시각만, 클릭 차단 (TASK-018).
            // TASK-019 fix 4차 — hover 시 원형 배경 (X 아이콘과 동일 패턴, 사용자 결정).
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.accent)
                .rotationEffect(.degrees(45))  // 곧은 압정 메타포
                .frame(width: DesignTokens.WindowSize.clipActionSize, height: DesignTokens.WindowSize.clipActionSize)
                .background(pinHovered ? DesignTokens.Colors.clipDeleteBgHover : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
                .onHover { isHover in
                    guard mode != .method3 else { return }
                    pinHovered = isHover
                }
                .highPriorityGesture(
                    TapGesture().onEnded {
                        if mode != .method3 { onTogglePin() }
                    }
                )
                // TASK-030 — 핀 해제 버튼 (pin.fill) 에 손가락 cursor. method3 비활성 분기 정합.
                .pointingHandCursor(enabled: mode != .method3)
                .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: pinHovered)
        } else {
            // 비핀: 선택된 행에서만 X 버튼 노출. 방식 2도 시각 노출하되 클릭 차단 (TASK-018 결정 1-A).
            if visuallySelected {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(deleteIconColor)
                    .frame(width: DesignTokens.WindowSize.clipActionSize, height: DesignTokens.WindowSize.clipActionSize)
                    .background(xHovered ? DesignTokens.Colors.clipDeleteBgHover : deleteBg)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onHover { isHover in
                        guard mode != .method3 else { return }
                        xHovered = isHover
                    }
                    // TASK-031 — outer onTapGesture 와 충돌 회피용 .highPriorityGesture 변환. 핀 버튼 패턴 정합.
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            if mode != .method3 { onDelete() }
                        }
                    )
                    // TASK-030 — X 삭제 버튼에 손가락 cursor. method3 비활성 분기 정합.
                    .pointingHandCursor(enabled: mode != .method3)
                    .allowsHitTesting(mode != .method3)
                    .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: xHovered)
            } else {
                Color.clear
                    .frame(width: DesignTokens.WindowSize.clipActionSize, height: DesignTokens.WindowSize.clipActionSize)
            }
        }
    }

    private var deleteBg: SwiftUI.Color { DesignTokens.Colors.clipDeleteBg }
    private var deleteIconColor: SwiftUI.Color { DesignTokens.Colors.clipDeleteIcon }

    // MARK: - Background / Border
    @ViewBuilder
    private var rowBackground: some View {
        if isFlashing {
            DesignTokens.Colors.pasteFlash
        } else if visuallySelected {
            LinearGradient(
                colors: [DesignTokens.Colors.clipRowSelectionTop, DesignTokens.Colors.clipRowSelectionBottom],
                startPoint: .top, endPoint: .bottom
            )
        } else if hovering {
            Color.primary.opacity(0.04)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        if isFlashing {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous)
                .stroke(DesignTokens.Colors.pasteFlashBorder, lineWidth: 0.5)
        } else if visuallySelected {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous)
                .stroke(DesignTokens.Colors.clipRowSelectionBorder, lineWidth: 0.5)
        }
    }
}
