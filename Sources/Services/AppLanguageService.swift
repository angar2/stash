// 앱 사용자 표시 언어 (한국어 / 영어) — UserDefaults bridge + 즉시 반영 메커니즘 (TASK-073)
import Foundation
import OSLog

/// 앱 사용자 표시 언어. UserDefaults `appLanguage` 영속 — OS 시스템 언어와 무관 고정.
/// `AccentColorMode` enum + setter 패턴 정합 (UX-UI §4-3).
enum AppLanguage: String {
    case korean = "ko"
    case english = "en"

    static let userDefaultsKey: String = "appLanguage"

    /// UserDefaults 조회 — 키 없음/잘못된 값 → `systemDefault` fallback.
    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let lang = AppLanguage(rawValue: raw) else {
            return systemDefault
        }
        return lang
    }

    /// OS 시스템 언어 자동 판별 — `Bundle.main.preferredLocalizations.first` 이 한국어 rawValue 면 `.korean`, 그 외 → `.english`.
    /// 첫 런칭 시 default 결정 로직 (사용자 명시 — TASK-073 Requirements).
    static var systemDefault: AppLanguage {
        if Bundle.main.preferredLocalizations.first == AppLanguage.korean.rawValue {
            return .korean
        }
        return .english
    }
}

/// 언어 적용 메커니즘 — UserDefaults override + `AppleLanguages` 즉시 반영 + Notification 발행.
/// AppKit 영역 (NSMenu / NSStatusItem 등) 은 `appLanguageDidChange` 노티 구독해 매뉴얼 재구성.
/// SwiftUI 영역은 `@AppStorage(AppLanguage.userDefaultsKey)` 의존성 등록 → body 자동 재평가.
enum AppLanguageService {
    /// 언어 변경 발행 — AppKit 영역 구독 시점.
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")

    /// 사용자 선택 변경 시 호출 — UserDefaults 갱신 + AppleLanguages override + Notification 발행.
    /// 이미 표시 중인 토스트 / 시스템 알림 잔존 알림 = 이전 언어 그대로 (TTL 만료 후 다음 호출부터 새 언어 — UX-UI §8 합리적 한계).
    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.userDefaultsKey)
        // AppleLanguages override — 다음 `String(localized:)` 호출부터 새 언어 lookup. macOS 표준 패턴.
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        NotificationCenter.default.post(name: appLanguageDidChange, object: nil)
        Logger.appLifecycle.info("AppLanguage applied: \(language.rawValue, privacy: .public)")
    }

    /// 앱 진입점 호출 — UserDefaults `appLanguage` 키 부재 시 `systemDefault` 박음 + `AppleLanguages` 적용.
    /// `StashApp.init` launch sequence 진입점에서 호출 (Phase 5).
    static func applyOnLaunch() {
        if UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) == nil {
            let def = AppLanguage.systemDefault
            UserDefaults.standard.set(def.rawValue, forKey: AppLanguage.userDefaultsKey)
            Logger.appLifecycle.info("AppLanguage initial: \(def.rawValue, privacy: .public) (systemDefault)")
        }
        let lang = AppLanguage.current
        UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        Logger.appLifecycle.info("AppLanguage applyOnLaunch: \(lang.rawValue, privacy: .public)")
    }
}
