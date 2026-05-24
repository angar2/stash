// i18n 키 lookup 헬퍼 (TASK-073 Phase 7) — 현재 AppLanguage 기반 .lproj Bundle 직접 lookup 으로 즉각 반영 보장
// 표준 `String(localized:)` 는 *현재 process Bundle.main preferredLocalization* lookup — `AppleLanguages` UserDefaults override 는 다음 process 시작 시에야 effective.
// 본 헬퍼는 *현재 process 안에서도* `AppLanguage.current` 기반 언어별 .lproj Bundle 을 직접 lookup — 사용자 환경설정 변경 즉시 새 언어 반환.
import Foundation

/// 현재 `AppLanguage` 기반 i18n 키 lookup. SwiftUI body 재평가 시점에 호출되면 자동 새 언어 반환.
/// fallback = `Bundle.main` (언어별 .lproj 미발견 시).
func L10n(_ key: String) -> String {
    let lang = AppLanguage.current.rawValue
    if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}
