// 설정 정보 탭 — settings.jsx S_About L386-421 정합
import SwiftUI

struct AboutTab: View {
    @Bindable var viewModel: SettingsViewModel
    /// TASK-073 — 앱 언어 변경 시 body 재평가 → 모든 i18n 키 lookup 새 언어.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 14) {
            // TASK-069 — 큰 앱 아이콘 (NSWorkspace 로 .app bundle 아이콘 추출 — DesignTokens stashAppIcon helper)
            Image.stashAppIcon
                .resizable()
                .frame(width: 88, height: 88)
                .padding(.top, 18)

            Text("Stash")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)

            // TASK-033 — *"버전"* 단어 제거. *"X.X.X (build Y)"* 형식만.
            Text("\(appVersion) (build \(appBuild))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)

            Text(L10n("about.description"))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(2)
                .padding(.top, 4)

            VStack(spacing: 8) {
                aboutButton(label: L10n("about.github"), icon: "link", action: viewModel.openGitHubRepo)
                aboutButton(label: L10n("about.dataFolder"), icon: "folder", action: viewModel.openDataFolder)
                aboutButton(label: L10n("about.releaseNotes"), icon: "doc.text", action: viewModel.openReleaseNotes)
            }
            .padding(.top, 4)
            .frame(maxWidth: 320)

            Text(L10n("about.copyright"))
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary.opacity(0.7))
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        // TASK-065 — hover fill 컴포넌트 (HoverFillCardButton) 정합.
        HoverFillCardButton(
            action: action,
            fill: DesignTokens.Colors.settingsCardBg,
            fillHover: DesignTokens.Colors.settingsCardBgHover
        ) {
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
            .foregroundStyle(DesignTokens.Colors.labelPrimary)
        }
    }
}
