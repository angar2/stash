// 다중 선택 프리뷰 바 (TASK-099) — 검색부 바로 아래, 클립 목록 위.
//
// 묶음 붙여넣기는 *실행하고 나서야* 결과를 아는 동작이라, 실행 전에 무엇이 어떤 순서로 붙는지 보여주는 것이
// 이 기능의 핵심 UX 다. 선택이 없으면 아예 그리지 않고(호출처가 분기), 그만큼 popover 높이가 자동으로 줄어든다.
//
// 검수 fix-3 — 초안은 바탕·보더·라벨·연결자가 전부 강조 색이라 파란색이 네 겹으로 겹쳐 산만했다.
// 바탕을 **검색바와 같은 어두운 톤** 으로 내리고, 강조 색은 *내용 칩* 하나에만 남겼다.
// 클립 하나 = 칩 하나이며 **연결자는 칩 밖** 에 옅게 둔다 — 이어붙일 문자가 내용과 섞여 읽히지 않도록.
import SwiftUI

struct SelectionPreviewBar: View {
    let preview: MultiPastePreview
    /// TASK-073 — 언어 변경 시 body 재평가 → `L10n()` 새 언어 lookup.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        let _ = appLanguageRaw
        return VStack(alignment: .leading, spacing: 0) {
            headerLine
            chipFlow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.previewBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous)
                .stroke(DesignTokens.Colors.previewBarBorder, lineWidth: 0.5)
        )
        // 검색바·클립 행·핀 행과 같은 좌우 inset — 세로 정렬선을 맞춘다.
        .padding(.horizontal, DesignTokens.Spacing.rowOuterHorzInset)
        .padding(.bottom, DesignTokens.Spacing.previewBarBottomGap)
    }

    // MARK: - 상단 라인 (선택 개수 + 실행 방식)

    /// 보조 정보라 회색 톤으로 둔다 — 강조 색을 쓰면 아래 칩과 시선을 다툰다.
    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(String(format: L10n("preview.count"), preview.selectionCount))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
            Spacer(minLength: 6)
            Text(modeLabel)
                .fontWeight(.medium)
                .foregroundStyle(DesignTokens.Colors.labelSecondary.opacity(0.72))
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, DesignTokens.Spacing.previewBarPaddingHorz)
        .padding(.top, DesignTokens.Spacing.previewBarPaddingVert)
    }

    /// 실행 방식 라벨. 파일 계열은 *선택 개수* 가 아니라 **실제로 붙는 파일 개수** 를 말한다
    /// (다중 파일 클립 하나가 여러 개로 펼쳐지므로 둘이 다르다).
    private var modeLabel: String {
        switch preview.mode {
        case .textJoin:
            return L10n("preview.mode.textJoin")
        case .fileBundle(let fileCount):
            return String(format: L10n("preview.mode.fileBundle"), fileCount)
        case .sequential(let fileCount):
            return String(format: L10n("preview.mode.sequential"), fileCount)
        }
    }

    // MARK: - 칩 영역

    /// 칩이 줄바꿈되며 흐르는 영역. 힌트바와 같은 `FlowLayout` 을 재사용한다.
    private var chipFlow: some View {
        FlowLayout(
            horizontalSpacing: DesignTokens.Spacing.previewChipGap,
            verticalSpacing: DesignTokens.Spacing.previewChipGap
        ) {
            ForEach(Array(preview.segments.enumerated()), id: \.offset) { idx, segment in
                // 조각 앞에 놓일 구분 표기 — `separators[idx - 1]` 이 이 조각과 앞 조각 사이다.
                // 빈 문자열이면 아무것도 그리지 않아 칩이 바로 붙는다.
                if idx > 0, let mark = separatorMark(before: idx) {
                    separatorLabel(mark)
                }
                chip(segment)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.previewBarPaddingHorz)
        .padding(.top, 4)
        .padding(.bottom, DesignTokens.Spacing.previewBarPaddingVert)
    }

    private func separatorMark(before idx: Int) -> String? {
        let i = idx - 1
        guard preview.separators.indices.contains(i) else { return nil }
        let mark = preview.separators[i]
        return mark.isEmpty ? nil : mark
    }

    /// 클립 하나. 긴 본문은 칩 안에서 말줄임한다 — 안 그러면 바가 세로로 부푼다.
    ///
    /// 색은 **계열로 갈린다** — 텍스트는 강조 색, 파일·이미지는 키캡과 같은 회색 톤(검수 결정).
    /// 텍스트는 이어붙여 하나가 되고 파일은 배열로 따로 붙는데, 색까지 같으면 그 차이가 화면에 안 드러난다.
    private func chip(_ segment: MultiPastePreview.Segment) -> some View {
        let isFile = segment.kind == .file
        return Text(segment.text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(isFile
                ? DesignTokens.Colors.previewFileChipForeground
                : DesignTokens.Colors.previewChipForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: DesignTokens.Spacing.previewChipMaxWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isFile
                        ? DesignTokens.Colors.previewFileChipBackground
                        : DesignTokens.Colors.previewChipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isFile
                        ? DesignTokens.Colors.previewFileChipBorder
                        : DesignTokens.Colors.previewChipBorder, lineWidth: 0.5)
            )
    }

    /// 칩 사이 구분 표기 — 배경 없이 옅게. 내용(칩)과 시각 위계를 분명히 가른다.
    private func separatorLabel(_ mark: String) -> some View {
        Text(mark)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(DesignTokens.Colors.labelSecondary.opacity(0.72))
            .lineLimit(1)
            .fixedSize()
    }
}
