// 클립 행 — popover.jsx L74-162 100% 정합
// 좌측 type icon (이미지=썸네일 그라데이션 36x32 / text·file=14px 라인) + 본문 (mono 분기) + 시간 (48px tabular) + Pin/X (선택 시만)
import SwiftUI

struct ClipRowView: View {
    let clip: Clip
    let isSelected: Bool
    let isFocused: Bool      // focusZone === "clip" 일 때만 시각 활성
    let isFlashing: Bool
    let mode: PopoverInvocationMode
    let onClick: () -> Void
    let onHover: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var hovering: Bool = false
    @State private var xHovered: Bool = false

    private var isMultiline: Bool {
        (clip.body ?? "").contains("\n") || (clip.body ?? "").count > 50
    }

    private var visuallySelected: Bool {
        isSelected && isFocused
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.rowInnerGap) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.rowInnerGap) {
                typeIconArea
                content
                Spacer(minLength: 4)
                timeLabel
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onClick)

            actionButton
        }
        .padding(.horizontal, DesignTokens.Spacing.rowPaddingMultiH)
        .padding(.vertical, isMultiline ? DesignTokens.Spacing.rowPaddingMultiV : 0)
        .frame(minHeight: DesignTokens.Spacing.rowMinHeight)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous))
        // hover 영역 명시 — outer 전체 (padding 포함, 시각 파란색 영역과 일치) 잡도록.
        .contentShape(Rectangle())
        .onHover { isHover in
            hovering = isHover
            if isHover { onHover() }
        }
        .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: visuallySelected)
        .animation(.easeInOut(duration: DesignTokens.Animation.clipRowSelectionFade), value: isFlashing)
    }

    // MARK: - Type icon
    @ViewBuilder
    private var typeIconArea: some View {
        switch clip.type {
        case .image:
            // 이미지 썸네일 — 36×32 그라데이션 (popover.jsx L80-89)
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
        case .text, .file:
            // 14×14 라인 아이콘 — file 타입은 *폴더 vs 파일* sub-분기 (TASK-016 D-7/D-8 fix v3, FileManager isDirectory 검사로 DB 모델 변경 X)
            ZStack {
                if clip.type == .file {
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
                Text(displayLines[idx])
                    .font(clip.type == .text && isMonoBody ? DesignTokens.Typography.clipBodyMono : DesignTokens.Typography.clipBody)
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        switch clip.type {
        case .image:
            return [clip.body ?? String(localized: "clip.row.image")]
        case .file:
            let name = clip.fileOriginalPath.flatMap { ($0 as NSString).lastPathComponent } ?? (clip.body ?? String(localized: "clip.row.file"))
            return [name]
        case .text:
            let body = clip.body ?? ""
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return Array(lines.prefix(2))
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

    // MARK: - Action button (Pin or X) — Bug 2 fix v4
    // hit-test 영역 분리 (body의 outer/inner HStack 구조)에 더해 X·Pin에 .highPriorityGesture로 자식 우선권 명시 (이중 안전망).
    @ViewBuilder
    private var actionButton: some View {
        if clip.isPinned {
            // 핀 표시 (방식 2는 표시만, 클릭 X)
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.accent)
                .rotationEffect(.degrees(45))  // 곧은 압정 메타포
                .frame(width: DesignTokens.WindowSize.clipActionSize, height: DesignTokens.WindowSize.clipActionSize)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        if mode != .method2 { onTogglePin() }
                    }
                )
        } else if mode != .method2 {
            // 비핀: 선택된 행에서만 X 버튼 노출
            if visuallySelected {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(deleteIconColor)
                    .frame(width: DesignTokens.WindowSize.clipActionSize, height: DesignTokens.WindowSize.clipActionSize)
                    .background(xHovered ? DesignTokens.Colors.clipDeleteBgHover : deleteBg)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onHover { isHover in xHovered = isHover }
                    .onTapGesture(perform: onDelete)
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
