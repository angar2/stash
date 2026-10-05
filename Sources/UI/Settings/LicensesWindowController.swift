// 오픈소스 라이선스 창 (TASK-111) — 정보 탭 *오픈소스 라이선스* 링크로 연다.
// 설정 창 위 시트가 아니라 별도 창이다. 긴 전문을 읽는 동안 설정 창 크기에 묶이지 않고 크기를 조절할 수 있다.
import AppKit
import SwiftUI
import OSLog

@MainActor
final class LicensesWindowController {
    private var window: PreferencesWindow?

    /// 창 lazy 생성 + activate + 앞으로. 이미 열려 있으면 위치를 유지한 채 앞으로만 가져온다.
    func show() {
        Logger.ui.info("LicensesWindowController.show")
        let target = ensureWindow()
        // 앱 언어를 바꾼 뒤 다시 열 때 제목이 새 언어를 따르도록 매번 갱신한다.
        target.title = L10n("about.licenses.title")
        if !target.isVisible {
            target.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        target.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> PreferencesWindow {
        if let window { return window }
        let hosting = NSHostingController(rootView: LicensesView(licenses: OpenSourceLicenses.all))
        // ESC 닫기는 설정 창과 같은 `PreferencesWindow` 의 cancelOperation 을 재사용한다.
        let newWindow = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.contentViewController = hosting
        newWindow.setContentSize(NSSize(width: 560, height: 520))
        newWindow.contentMinSize = NSSize(width: 420, height: 320)
        newWindow.isReleasedWhenClosed = false
        self.window = newWindow
        return newWindow
    }
}

/// 라이브러리마다 이름 · 저장소 주소 · 라이선스 전문을 차례로 싣는다.
struct LicensesView: View {
    let licenses: [OpenSourceLicense]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(licenses) { license in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(license.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.labelPrimary)
                        Text(license.url)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.labelSecondary)
                        Text(license.text)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.labelPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .textSelection(.enabled)
                    .accessibilityIdentifier("licenses.\(license.name)")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
