// 클립 행 — popover.jsx L74-162 100% 정합
// 좌측 type icon (이미지=NSImage 썸네일 36x32 + 로드 실패 시 그라데이션 fallback / text·file=14px 라인) + 본문 (mono 분기) + 시간 (48px tabular) + Pin/X (선택 시만)
import SwiftUI
import AppKit

struct ClipRowView: View, Equatable {
    let clip: Clip
    let isSelected: Bool
    let isFocused: Bool      // focusZone === "clip" 일 때만 시각 활성
    let mode: PopoverInvocationMode
    /// 시간 라벨 표시 여부 — Pin 사이드바(220 너비) 안에서는 false 박아 본문 truncate 완화 (TASK-019 fix 3차 B8).
    var showTimeLabel: Bool = true
    /// TASK-035 — 검색바 입력 검색어. 비어있지 않으면 본문 매칭 구간을 accent 전경 + semibold 로 강조. Pin 사이드바는 항상 "" 전달 (UX-UI §7-3 적용 범위 제외).
    var searchQuery: String = ""
    let onClick: () -> Void
    let onHover: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    /// TASK-055 — hover 임계 trigger 진입점. 부모가 clip.id capture 해 `viewModel.hoverEnterRow(id:)` / `hoverExitRow(id:)` 호출.
    /// default no-op — 호출처 (HistoryPopover / PinSidebarView) 가 박지 않으면 hover 트리거 비활성.
    var onHoverEnter: () -> Void = {}
    var onHoverExit: () -> Void = {}
    /// TASK-098 — Pin 사이드바 순번 (1~10). 타입 아이콘 *오른쪽*, 본문 왼쪽에 표시. nil = 미표시 (본체 목록 기본값 → 영향 0).
    var pinOrdinal: Int? = nil
    /// TASK-098 — 본문 자리에 값 대신 표시할 문자열 (핀 명칭). nil = 기존대로 값 표시.
    var displayTitleOverride: String? = nil
    /// TASK-098 — 압정 앞 조합 키캡 문자열 (`⌥⌘1` 등). nil = 미표시.
    var shortcutKeycap: String? = nil
    /// TASK-098 — 키캡이 *사용자가 바꾼* 조합인지. 기본 조합은 옅게 / 변경 조합은 진하게.
    var isKeycapCustomized: Bool = false

    /// TASK-037 fix-15b — Equatable conformance. closure 제외 시각 영향 prop 만 비교.
    /// `.equatable()` modifier 와 함께 사용 → SwiftUI 가 변경된 행만 re-render → 호버 응답 빠름 (selectedIdx 변경 시 다른 행 skip).
    /// Swift 6 concurrency — `nonisolated` 박아 MainActor 격리 외 호출 허용.
    /// TASK-053 fix-3 — accentColorMode 변경 시 부모 root `.id` 변경으로 view tree 강제 재생성 → ClipRowView 자체 새 instance — Equatable 비교 무관.
    nonisolated static func == (lhs: ClipRowView, rhs: ClipRowView) -> Bool {
        lhs.clip == rhs.clip &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isFocused == rhs.isFocused &&
        lhs.mode == rhs.mode &&
        lhs.showTimeLabel == rhs.showTimeLabel &&
        lhs.searchQuery == rhs.searchQuery &&
        // TASK-098 — 순번·표시 문자열·키캡도 시각 영향 prop. 빠지면 조합 변경·명칭 변경이 행에 반영되지 않는다.
        lhs.pinOrdinal == rhs.pinOrdinal &&
        lhs.displayTitleOverride == rhs.displayTitleOverride &&
        lhs.shortcutKeycap == rhs.shortcutKeycap &&
        lhs.isKeycapCustomized == rhs.isKeycapCustomized
    }

    @State private var hovering: Bool = false
    @State private var xHovered: Bool = false
    /// TASK-019 fix 4차 — 핀 아이콘 hover state. 본체 + Pin 사이드바 양쪽 동일 (사용자 결정).
    @State private var pinHovered: Bool = false
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 본 행 body 재평가 트리거 (선택 그라데이션 / Pin 아이콘 / multi-file 캡슐 / 검색 매칭 즉시 갱신).
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue
    /// TASK-073 — 언어 변경 시 body 재평가 → L10n() 새 언어 lookup ("이미지" 라벨 등).
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    private var visuallySelected: Bool {
        isSelected && isFocused
    }

    var body: some View {
        let _ = accentColorModeRaw  // TASK-053 SwiftUI 의존성 등록
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return HStack(alignment: .center, spacing: DesignTokens.Spacing.rowInnerGap) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.rowInnerGap) {
                // TASK-098 fix-1 — 순번이 행의 **가장 좌측** (타입 아이콘보다 앞). 사용자 검수 지시.
                if let pinOrdinal {
                    Text("\(pinOrdinal)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.labelSecondary)
                        .frame(width: 13, alignment: .center)
                }
                typeIconArea
                content
                Spacer(minLength: 4)
                if showTimeLabel {
                    timeLabel
                }
                // TASK-098 — 현재 지정된 Pin 직접 paste 조합. 압정 앞.
                if let shortcutKeycap {
                    keycapLabel(shortcutKeycap)
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
        .onHover { isHover in
            hovering = isHover
            if isHover {
                onHover()
                onHoverEnter()  // TASK-055 hover 임계 timer 시작.
            } else {
                onHoverExit()  // TASK-055 같은 행 이탈 시 timer cancel.
            }
        }
        // TASK-037 fix-16 — visuallySelected animation 폐기. 호버 시 highlight 가 120ms fade 거쳐서 *마우스 지나간 후 뒤늦게 색 변경* 인식. 즉시 highlight 박힘.
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
    /// TASK-082 Phase 3 — `NSImage(contentsOfFile:)` 풀해상도 로드 → `ThumbnailCache.shared.thumbnail(for:targetSize:)` 다운스케일 + LRU 캐시.
    /// 메모리 footprint 차단 (200 행 × 풀해상도 누적 약 1.5GB → 다운스케일 누적 약 2.4MB). 반환 타입 `NSImage?` 동일 — if-let 분기 + fallback 구조 100% 보존. PinSidebarView 가 ClipRowView 재사용이라 자연 혜택 (M4) + PopoverPanel.mount rebuild 시도 캐시 hit (M5).
    @ViewBuilder
    private var imageThumbnail: some View {
        let thumbnailTarget = NSSize(
            width: DesignTokens.WindowSize.clipImageThumbW,
            height: DesignTokens.WindowSize.clipImageThumbH
        )
        if let path = clip.filePath, let nsImage = ThumbnailCache.shared.thumbnail(for: path, targetSize: thumbnailTarget) {
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

    /// TASK-082 Phase 7 (C1) fix-1 — 디렉토리 여부 캐시. body 평가마다 동기 `FileManager.fileExists` 디스크 I/O 호출 회피.
    /// `@State + onAppear` 패턴이 1-frame `doc → folder` flicker 가능성 → static cache + computed property 동기 반환으로 변경.
    /// cache miss 시 디스크 I/O 1회 + 박음 / hit 시 즉시 반환. path 가 UUID 파일명이라 *동일 path 재사용* X — stale cache 영향 0.
    @MainActor
    private static var directoryCheckCache: [String: Bool] = [:]

    /// .file 클립의 path가 폴더인지 일반 파일인지 — fileOriginalPath 우선, 없으면 filePath fallback. 둘 다 없으면 false (doc 아이콘).
    /// TASK-082 Phase 7 (C1) — static cache 적용. body 첫 평가 시점에 동기 결정 + 즉시 반환.
    private var isFileADirectory: Bool {
        let path = clip.fileOriginalPath ?? clip.filePath
        guard let path else { return false }
        if let cached = Self.directoryCheckCache[path] {
            return cached
        }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let result = exists && isDir.boolValue
        Self.directoryCheckCache[path] = result
        return result
    }

    private var typeIconColor: SwiftUI.Color {
        visuallySelected ? DesignTokens.Colors.clipTypeIconSelected : DesignTokens.Colors.clipIconUnselected
    }

    // MARK: - Content
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // TASK-098 — 핀 명칭이 지정된 행은 값 대신 명칭을 표시한다 (중간 굵기 + 본문 색).
            // 붙여넣기·복사는 언제나 실제 값으로 동작하므로 *표시만* 바뀐다. 검색 강조는 값 영역이 아니라 미적용.
            if let displayTitleOverride {
                Text(displayTitleOverride)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(displayLines.indices, id: \.self) { idx in
                    Text(highlightedLine(idx))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// TASK-098 — 조합 키캡. 기본 조합은 옅게 / 사용자가 바꾼 조합은 진하게 (어디를 손댔는지 한눈에).
    private func keycapLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(
                isKeycapCustomized
                    ? DesignTokens.Colors.labelPrimary.opacity(0.80)
                    : DesignTokens.Colors.labelSecondary
            )
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DesignTokens.Colors.pinKeycapBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isKeycapCustomized
                            ? DesignTokens.Colors.labelPrimary.opacity(0.30)
                            : DesignTokens.Colors.labelSecondary.opacity(0.32),
                        lineWidth: 0.5
                    )
            )
            .fixedSize()
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
    nonisolated static func imageDisplayName(for clip: Clip) -> String {
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
        return L10n("clip.row.image")
    }

    /// 클립 표시 문자열 **단일 진실 소스** — 타입별 라벨 규칙만 결정하고 *줄 처리는 호출처* 가 한다
    /// (클립 행은 첫 줄만, 설정 PIN 단축키 행은 개행을 공백으로 접음).
    /// TASK-098 — 설정 PIN 단축키 행이 자체 구현을 갖고 있어 **이미지 핀에 내부 UUID 파일명**이,
    /// **다중 파일 묶음에 첫 파일명**이 노출됐다(본체 목록은 *이미지* / *여러 파일* 라벨). 규칙을 여기로 모아 재발 차단.
    nonisolated static func displayLabel(for clip: Clip) -> String {
        switch clip.type {
        case .image:
            return imageDisplayName(for: clip)
        case .file:
            // TASK-026 — 다중 파일 묶음 라벨 = `여러 파일` (단순 라벨, N 정보는 배지가 담당).
            // 파일명 리스트 상세는 TASK-027 *클립 상세 미리보기 sub-window* 에서 별도 표시.
            if clip.isMultiFile {
                return L10n("clip.row.multiFile.label")
            }
            return clip.fileOriginalPath.map { ($0 as NSString).lastPathComponent }
                ?? (clip.body ?? L10n("clip.row.file"))
        case .text:
            return clip.body ?? ""
        }
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
        let label = Self.displayLabel(for: clip)
        guard clip.type == .text else { return [label] }
        // TASK-037 — 행 단일 고정 높이 정책. 첫 줄만 노출, 초과는 truncate.
        return [label.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""]
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
        if interval < 60 { return L10n("time.now") }
        if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)\(L10n("time.suffix.minutes"))"
        }
        if interval < 86_400 {
            let hours = Int(interval / 3600)
            return "\(hours)\(L10n("time.suffix.hours"))"
        }
        if interval < 86_400 * 2 {
            return L10n("time.yesterday")
        }
        let days = Int(interval / 86_400)
        return "\(days)\(L10n("time.suffix.days"))"
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
        if visuallySelected {
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
        if visuallySelected {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous)
                .stroke(DesignTokens.Colors.clipRowSelectionBorder, lineWidth: 0.5)
        }
    }
}
