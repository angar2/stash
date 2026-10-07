// 앱 밖으로 여는 주소 (TASK-116) — 정보 탭 항목이 여는 주소를 한 곳에 모은다.
// 주소 자체는 두 판 모두에 있다. 어느 판에서 어떤 항목을 보일지는 화면 쪽(AboutTab)이 정한다.
import Foundation

enum AppLinks {
    /// 공개 소스 저장소 (`정보` 탭 *GitHub 저장소 열기*).
    static let gitHubRepository = URL(string: "https://github.com/angar2/stash")!

    /// 개인정보 처리방침 (`정보` 탭 *개인정보 처리방침*). 가이드라인 5.1.1(i) — App Store Connect 칸과 앱 안에 모두 둔다.
    /// 리포 루트 `PRIVACY.md` 를 main 브랜치 기준으로 연다. main 에 들어가기 전에는 GitHub 가 404 를 낸다.
    static let privacyPolicy = URL(string: "https://github.com/angar2/stash/blob/main/PRIVACY.md")!

    /// App Store 앱의 Stash 상품 페이지 (App Store판 `정보` 탭 *App Store에서 보기*).
    /// `itms-apps` 주소는 브라우저를 거치지 않고 App Store 앱을 연다. 앱 번호는 App Store Connect 앱 기록의 Apple ID다.
    static let appStorePage = URL(string: "itms-apps://apps.apple.com/app/id6819763048")!
}
