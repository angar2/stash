// 업데이트 배너 (TASK-102) — popover 헤더 안, 로고 행 아래·검색부 위.
//
// 상주형 메뉴바 앱이라 새 버전을 찾았다고 창을 띄우면 사용자가 하던 작업을 끊는다.
// 그래서 발견 사실만 이 한 줄로 알리고, 창은 사용자가 눌렀을 때 연다 (UX-UI *자동 업데이트*).
//
// **배너 전체가 눌린다** — 작은 버튼을 정확히 겨냥하게 만들지 않는다. 닫기(`×`)만 따로 눌린다.
// 대기 중인 버전이 없으면 호출처가 아예 그리지 않고, 그만큼 popover 높이가 자동으로 줄어든다.
import SwiftUI

struct UpdateBannerView: View {
    /// 표시할 새 버전 (예 `1.3.0`).
    let version: String
    /// 배너 본문을 눌렀을 때 — 표준 업데이트 창을 연다.
    let onOpen: () -> Void
    /// 닫기(`×`) — 이 버전은 다시 알리지 않는다.
    let onDismiss: () -> Void

    /// TASK-073 — 언어 변경 시 body 재평가 → `L10n()` 새 언어 lookup.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue
    @State private var bannerHovered = false
    @State private var closeHovered = false

    var body: some View {
        let _ = appLanguageRaw
        return HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.updateBannerVersionForeground)
            messageText
            Spacer(minLength: 6)
            actionChip
            closeButton
        }
        .padding(.horizontal, DesignTokens.Spacing.updateBannerPaddingHorz)
        .frame(height: DesignTokens.Spacing.updateBannerHeight)
        .frame(maxWidth: .infinity)
        .background(bannerHovered ? DesignTokens.Colors.updateBannerBackgroundHover : DesignTokens.Colors.updateBannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.clipRow, style: .continuous)
                .stroke(DesignTokens.Colors.updateBannerBorder, lineWidth: 0.5)
        )
        // 배너 전체가 눌리는 영역. 닫기 버튼은 자체 `onTapGesture` 로 이 제스처보다 먼저 받는다.
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { bannerHovered = $0 }
        // 위 간격은 로고 행의 얕은 하단 여백(2)을 보완한다 — 아래 간격과 같은 8 이 되도록.
        .padding(.top, DesignTokens.Spacing.updateBannerTopGap)
        .padding(.bottom, DesignTokens.Spacing.updateBannerBottomGap)
        .accessibilityIdentifier("popover.updateBanner")
    }

    // MARK: - 조각

    /// 버전 번호만 강조한다 — 배너에서 가장 먼저 읽혀야 하는 정보다.
    /// 앞뒤 문구를 각각 키로 두어 언어마다 어순을 지킨다
    /// (한국어 *새 버전 1.3.0 이 있습니다* / 영어 *Version 1.3.0 is available*).
    private var messageText: some View {
        (
            Text(L10n("update.banner.prefix"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.labelPrimary)
            + Text(version)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(DesignTokens.Colors.updateBannerVersionForeground)
            + Text(L10n("update.banner.suffix"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.labelPrimary)
        )
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityIdentifier("popover.updateBanner.message")
    }

    private var actionChip: some View {
        Text(L10n("update.banner.action"))
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(DesignTokens.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityIdentifier("popover.updateBanner.action")
    }

    /// 닫기는 **원형** 이다 (검수 2026-08-02) — 사각 hover 배경이 배너 안 다른 사각 요소(업데이트 버튼)와
    /// 겹쳐 읽혀 어수선했다.
    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(closeHovered ? DesignTokens.Colors.labelPrimary : DesignTokens.Colors.labelSecondary)
            .frame(width: 16, height: 16)
            .background(closeHovered ? DesignTokens.Colors.popoverActionButtonHoverBg : Color.clear)
            .clipShape(Circle())
            .contentShape(Circle())
            .onHover { closeHovered = $0 }
            .onTapGesture { onDismiss() }
            .accessibilityIdentifier("popover.updateBanner.close")
    }
}
