// 설정 개인정보 탭 — settings.jsx S_Privacy L280-384 정합
import SwiftUI

struct PrivacyTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 14) {
            transientNote
            blockedAppsCard
        }
    }

    // TransientType 그린 안내 박스
    private var transientNote: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.toastSuccess.opacity(0.18))
                    .frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.toastSuccess)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "privacy.transient.title"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                Text(String(localized: "privacy.transient.body"))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.toastSuccess.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.Colors.toastSuccess.opacity(0.25), lineWidth: 0.5)
                )
        )
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
                Button(action: { viewModel.selectAppFromOpenPanel() }) {
                    Text(String(localized: "privacy.blocked.addApp"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                                .fill(DesignTokens.Colors.settingsCardBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                                        .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
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
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.7), Color.gray.opacity(0.4)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bundleId)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                            }
                            Spacer()
                            Button(action: { viewModel.removeBlockedApp(bundleId: bundleId) }) {
                                Text(String(localized: "privacy.blocked.remove"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.toastError)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                                            .fill(DesignTokens.Colors.toastError.opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
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
}
