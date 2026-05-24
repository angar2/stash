// TASK-073 — AppLanguage enum + AppLanguageService apply/applyOnLaunch + SettingsViewModel.setAppLanguage 통합 검증
// 두 Suite 간 UserDefaults 공유 자원 parallel race 회피 위해 단일 Suite 로 통합.
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("AppLanguageService", .serialized)
struct AppLanguageServiceTests {
    private func cleanUserDefaults() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        UserDefaults.standard.removeObject(forKey: "autoPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "clipsPerPage")
        UserDefaults.standard.removeObject(forKey: "autoFitClipListHeight")
        UserDefaults.standard.removeObject(forKey: "hintBarVisible")
    }

    private func makeViewModel() -> SettingsViewModel {
        cleanUserDefaults()
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        return SettingsViewModel(loginItemService: svc)
    }

    @Test("AppLanguage.korean.rawValue == 'ko'")
    func koreanRawValue() {
        #expect(AppLanguage.korean.rawValue == "ko")
    }

    @Test("AppLanguage.english.rawValue == 'en'")
    func englishRawValue() {
        #expect(AppLanguage.english.rawValue == "en")
    }

    @Test("AppLanguage.current — UserDefaults 값 부재 시 systemDefault 반환")
    func currentAbsentReturnsSystemDefault() {
        cleanUserDefaults()
        #expect(AppLanguage.current == AppLanguage.systemDefault)
        cleanUserDefaults()
    }

    @Test("AppLanguage.current — UserDefaults 'en' 저장 시 .english 반환")
    func currentValidReturnsValue() {
        cleanUserDefaults()
        UserDefaults.standard.set("en", forKey: AppLanguage.userDefaultsKey)
        #expect(AppLanguage.current == .english)
        cleanUserDefaults()
    }

    @Test("AppLanguage.current — UserDefaults 잘못된 값 시 systemDefault fallback")
    func currentInvalidFallsBack() {
        cleanUserDefaults()
        UserDefaults.standard.set("fr", forKey: AppLanguage.userDefaultsKey)
        #expect(AppLanguage.current == AppLanguage.systemDefault)
        cleanUserDefaults()
    }

    @Test("AppLanguageService.apply — UserDefaults 갱신 + AppleLanguages override + Notification 발행")
    func applySavesAndPostsNotification() async {
        cleanUserDefaults()
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: AppLanguageService.appLanguageDidChange,
            object: nil,
            queue: .main
        ) { _ in counter.increment() }
        defer {
            NotificationCenter.default.removeObserver(observer)
            cleanUserDefaults()
        }

        AppLanguageService.apply(.english)

        // Notification 비동기 발행 — main queue drain 대기 (200ms — CI 환경 안정 여유)
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) == "en")
        let appleLangs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        #expect(appleLangs?.first == "en")
        #expect(counter.count == 1)
    }

    // MARK: - SettingsViewModel 통합 (TASK-073)

    @Test("SettingsViewModel.loadAppLanguage — UserDefaults 부재 시 systemDefault state 적용")
    func vmLoadAbsentSetsSystemDefault() {
        let vm = makeViewModel()
        #expect(vm.appLanguage == AppLanguage.systemDefault)
        cleanUserDefaults()
    }

    @Test("SettingsViewModel.loadAppLanguage — UserDefaults 'en' 저장 시 .english state 적용")
    func vmLoadPersistedValue() {
        cleanUserDefaults()
        UserDefaults.standard.set("en", forKey: AppLanguage.userDefaultsKey)
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        let vm = SettingsViewModel(loginItemService: svc)
        #expect(vm.appLanguage == .english)
        cleanUserDefaults()
    }

    @Test("SettingsViewModel.setAppLanguage — state + UserDefaults + AppleLanguages override + Notification 발행")
    func vmSetterSyncsAll() async {
        let vm = makeViewModel()
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: AppLanguageService.appLanguageDidChange,
            object: nil,
            queue: .main
        ) { _ in counter.increment() }
        defer {
            NotificationCenter.default.removeObserver(observer)
            cleanUserDefaults()
        }

        vm.setAppLanguage(.english)
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.appLanguage == .english)
        #expect(UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) == "en")
        let appleLangs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        #expect(appleLangs?.first == "en")
        #expect(counter.count == 1)
    }
}

/// Notification observer closure 안 카운트 캡쳐용 reference type. var 캡쳐 strict concurrency 회피.
final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func increment() { lock.lock(); _count += 1; lock.unlock() }
}
