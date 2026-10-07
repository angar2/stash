// TASK-116 — 정보 탭이 여는 앱 밖 주소. 한 글자만 틀려도 심사관·사용자가 엉뚱한 곳에 가므로 값을 그대로 대조한다.
import Testing
import Foundation
@testable import stash

@Suite("AppLinks")
struct AppLinksTests {
    @Test("개인정보 처리방침 — main 브랜치의 리포 루트 PRIVACY.md")
    func privacyPolicy() {
        #expect(AppLinks.privacyPolicy.absoluteString == "https://github.com/angar2/stash/blob/main/PRIVACY.md")
    }

    @Test("App Store에서 보기 — itms-apps 로 App Store 앱의 앱 번호 6819763048 페이지")
    func appStorePage() {
        #expect(AppLinks.appStorePage.scheme == "itms-apps")
        #expect(AppLinks.appStorePage.absoluteString == "itms-apps://apps.apple.com/app/id6819763048")
    }

    @Test("GitHub 저장소 — 기존 주소 그대로")
    func gitHubRepository() {
        #expect(AppLinks.gitHubRepository.absoluteString == "https://github.com/angar2/stash")
    }
}
