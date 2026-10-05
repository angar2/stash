// 배포판 구분 (TASK-112) — 같은 소스에서 직접 배포(dmg)판과 App Store판을 빌드한다.
// 판은 빌드 타깃의 컴파일 조건 `APP_STORE` 로만 정한다 (project.yml `StashAppStore` 타깃).
//
// 업데이트 요소처럼 App Store판에서 *코드째* 빠져야 하는 것은 이 값이 아니라 `#if !APP_STORE` 로 감싼다.
// 이 값은 두 판 모두에 있는 코드가 판에 따라 다른 데이터를 고를 때 쓴다 (예: 오픈소스 라이선스 목록).
enum AppDistribution: Equatable {
    /// GitHub dmg 직접 배포판 — Sparkle 자동 업데이트 포함.
    case direct
    /// Mac App Store판 — 업데이트는 App Store 가 맡는다 (가이드라인 2.4.5(vii)).
    case appStore

    static var current: AppDistribution {
        #if APP_STORE
        .appStore
        #else
        .direct
        #endif
    }
}
