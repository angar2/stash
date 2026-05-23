// 설정 개인정보 탭 — TASK-033 정합 (*비밀번호 자동 제외 안내 박스* 폐기 + *저장하지 않을 앱* 텍스트 / 아이콘+한글 이름 표시)
import SwiftUI
import AppKit

struct PrivacyTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 14) {
            blockedAppsCard
        }
    }

    private var blockedAppsCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "privacy.blocked.title"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    Text(String(localized: "privacy.blocked.subtitle"))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.labelSecondary)
                }
                Spacer()
                // TASK-065 — *앱 추가* 카드형 버튼. hover 시 배경 톤 진하게.
                HoverFillCardButton(
                    action: { viewModel.selectAppFromOpenPanel() },
                    fill: DesignTokens.Colors.settingsCardBg,
                    fillHover: DesignTokens.Colors.settingsCardBgHover
                ) {
                    Text(String(localized: "privacy.blocked.addApp"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)

            if viewModel.blockedAppBundleIds.isEmpty {
                Text(String(localized: "privacy.blocked.empty"))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.blockedAppBundleIds.enumerated()), id: \.element) { idx, bundleId in
                        HStack(spacing: 10) {
                            // TASK-033 — 앱 아이콘 (NSWorkspace.shared.icon(forFile:)) + 한글 이름 (FileManager.displayName). 번들 ID raw 표시 X.
                            if let icon = Self.appIcon(for: bundleId) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                            } else {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color.gray.opacity(0.7), Color.gray.opacity(0.4)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 22, height: 22)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.appDisplayName(for: bundleId))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                            }
                            Spacer()
                            // TASK-065 — *삭제* 버튼 (toastError 톤). hover 시 배경 opacity 진하게. stroke X.
                            HoverFillCardButton(
                                action: { viewModel.removeBlockedApp(bundleId: bundleId) },
                                fill: DesignTokens.Colors.toastError.opacity(0.10),
                                fillHover: DesignTokens.Colors.toastError.opacity(0.20),
                                stroke: nil
                            ) {
                                Text(String(localized: "privacy.blocked.remove"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.toastError)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if idx < viewModel.blockedAppBundleIds.count - 1 {
                            Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                        }
                    }
                }
            }
        }
        .background(DesignTokens.Colors.settingsCardBg)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsCard, style: .continuous)
                .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
        )
    }

    // MARK: - App icon / name lookup (TASK-033)

    /// 번들 ID → 앱 아이콘. urlForApplication → icon(forFile:). 앱 미설치 시 nil.
    private static func appIcon(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 번들 ID → 앱 표시 이름 (한글 환경 = 한글 이름). FileManager.displayName 활용. 앱 미설치 시 번들 ID raw fallback.
    private static func appDisplayName(for bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path)
    }
}

