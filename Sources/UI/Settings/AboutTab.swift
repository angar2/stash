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
                .accessibilityIdentifier("about.appName")

            // TASK-033 — *"버전"* 단어 제거. *"X.X.X (build Y)"* 형식만.
            Text("\(appVersion) (build \(appBuild))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .accessibilityIdentifier("about.version")

            Text(L10n("about.description"))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(2)
                .padding(.top, 4)

            VStack(spacing: 8) {
                // TASK-102 — 나머지 세 항목은 자료를 여는 것이고 이 항목만 동작을 일으키므로 맨 위에 둔다.
                // 결과는 같은 자리 우측 문구로 알린다 — 결과 하나 보자고 창을 띄우지 않는다 (UX-UI *자동 업데이트*).
                if viewModel.updateAvailable {
                    updateCheckButton
                }
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

    /// TASK-102 — *업데이트 확인*. 다른 항목과 같은 형태를 쓰되, 우측에 확인 상태 문구가 붙는다.
    /// 확인 중에는 항목을 비활성으로 두어 연타를 막는다.
    private var updateCheckButton: some View {
        let state = viewModel.updateCheckState
        let isChecking = (state == .checking)
        return HoverFillCardButton(
            action: viewModel.checkForUpdates,
            fill: DesignTokens.Colors.settingsCardBg,
            fillHover: DesignTokens.Colors.settingsCardBgHover
        ) {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(isChecking ? L10n("about.update.checking") : L10n("about.update.check"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if let label = outcomeLabel(for: state) {
                    Text(label.text)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(label.color)
                        .accessibilityIdentifier("about.update.outcome")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(DesignTokens.Colors.labelPrimary)
        }
        .disabled(isChecking)
        .opacity(isChecking ? 0.55 : 1)
        .accessibilityIdentifier("about.update.check")
    }

    /// 확인 결과 문구. 실패만 경고 톤이고 나머지는 보조 톤이다.
    private func outcomeLabel(for state: ManualUpdateCheckState?) -> (text: String, color: Color)? {
        switch state {
        case .upToDate:
            return (L10n("about.update.upToDate"), DesignTokens.Colors.labelSecondary)
        case .failed:
            return (L10n("about.update.failed"), DesignTokens.Colors.toastWarn)
        case .checking, nil:
            return nil
        }
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
