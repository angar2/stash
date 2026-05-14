// 설정 정보 탭 — settings.jsx S_About L386-421 정합
import SwiftUI

struct AboutTab: View {
    @Bindable var viewModel: SettingsViewModel

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 14) {
            // 큰 적층 카드 컬러 아이콘 (variant 1)
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 13/255, green: 111/255, blue: 255/255),
                                Color(red: 100/255, green: 50/255, blue: 200/255)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: DesignTokens.Colors.accent.opacity(0.35), radius: 14, y: 6)
                TrayIconView(full: true, size: 48)
                    .foregroundStyle(.white)
            }
            .padding(.top, 18)

            Text("stash")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)

            Text(String(localized: "about.version") + " \(appVersion) (build \(appBuild))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)

            Text(String(localized: "about.description"))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(2)
                .padding(.top, 4)

            VStack(spacing: 8) {
                aboutButton(label: String(localized: "about.github"), icon: "link", action: viewModel.openGitHubRepo)
                aboutButton(label: String(localized: "about.dataFolder"), icon: "folder", action: viewModel.openDataFolder)
                aboutButton(label: String(localized: "about.releaseNotes"), icon: "doc.text", action: {})
            }
            .padding(.top, 4)
            .frame(maxWidth: 320)

            Text(String(localized: "about.copyright"))
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary.opacity(0.7))
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                    .fill(DesignTokens.Colors.settingsCardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                            .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
                    )
            )
            .foregroundStyle(DesignTokens.Colors.labelPrimary)
        }
        .buttonStyle(.plain)
    }
}
