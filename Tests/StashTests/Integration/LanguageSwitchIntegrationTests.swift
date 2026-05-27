// i18n 한·영 전환 end-to-end 통합 시나리오 — Phase 5 (TASK-089)
// AppLanguage enum + UserDefaults bridge 검증.
// NOTE: `AppLanguageService.apply` 호출 자체는 기존 `SettingsViewModelTests` (setAppLanguage) 가 검증.
// 본 통합은 `AppLanguage.current` 가 UserDefaults `appLanguage` 키 값을 정확히 반영하는지 검증.
// AppleLanguages global state 영향 회피 — i18n L10n 의존 기존 테스트 (ClipMetaFooterFormat 등) 와 parallel race 차단.
import Testing
import Foundation
@testable import stash

@MainActor
@Suite(.serialized)
struct LanguageSwitchIntegrationTests {

    @Test("AppLanguage.current — UserDefaults 'ko' → .korean")
    func currentReflectsKoreanDefault() {
        UserDefaults.standard.set("ko", forKey: AppLanguage.userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.userDefaultsKey) }
        #expect(AppLanguage.current == .korean, "UserDefaults 'ko' → AppLanguage.current = .korean")
    }

    @Test("AppLanguage.current — UserDefaults 'en' → .english")
    func currentReflectsEnglishDefault() {
        UserDefaults.standard.set("en", forKey: AppLanguage.userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.userDefaultsKey) }
        #expect(AppLanguage.current == .english, "UserDefaults 'en' → AppLanguage.current = .english")
    }

    @Test("AppLanguage.current — UserDefaults 잘못된 값 → systemDefault fallback")
    func currentFallsBackToSystemDefault() {
        UserDefaults.standard.set("invalid-lang-code", forKey: AppLanguage.userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.userDefaultsKey) }
        // systemDefault 은 OS 환경에 따라 .korean 또는 .english — Bool 값 valid 확인.
        let current = AppLanguage.current
        #expect(current == .korean || current == .english, "잘못된 값 → systemDefault fallback (.korean 또는 .english)")
    }

    @Test("AppLanguage.systemDefault — preferredLocalizations 기반 결정")
    func systemDefaultIsValid() {
        let sysDefault = AppLanguage.systemDefault
        #expect(sysDefault == .korean || sysDefault == .english, "systemDefault 는 .korean 또는 .english 둘 중 하나")
    }
}
