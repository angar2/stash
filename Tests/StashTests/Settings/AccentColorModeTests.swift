// TASK-053 — AccentColorMode enum + SettingsViewModel.setAccentColorMode UserDefaults sync + Notification 발행 검증
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("AccentColorMode", .serialized)
struct AccentColorModeTests {
    private func cleanUserDefaults() {
        UserDefaults.standard.removeObject(forKey: AccentColorMode.userDefaultsKey)
    }

    private func makeViewModel() -> SettingsViewModel {
        cleanUserDefaults()
        // Display preferences 영향 회피 (loadDisplayPreferences 에서 다른 키도 조회)
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        UserDefaults.standard.removeObject(forKey: "autoPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "clipsPerPage")
        UserDefaults.standard.removeObject(forKey: "autoFitClipListHeight")
        UserDefaults.standard.removeObject(forKey: "hintBarVisible")
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        return SettingsViewModel(loginItemService: svc)
    }

    @Test("AccentColorMode.current — 키 없으면 .default")
    func defaultWhenAbsent() {
        cleanUserDefaults()
        #expect(AccentColorMode.current == .default)
    }

    @Test("AccentColorMode.current — 'system' 저장 시 .system 반환")
    func systemMode() {
        cleanUserDefaults()
        UserDefaults.standard.set("system", forKey: AccentColorMode.userDefaultsKey)
        #expect(AccentColorMode.current == .system)
        cleanUserDefaults()
    }

    @Test("AccentColorMode.current — 잘못된 값 저장 시 .default fallback")
    func invalidValueFallsBack() {
        cleanUserDefaults()
        UserDefaults.standard.set("invalid-mode-xyz", forKey: AccentColorMode.userDefaultsKey)
        #expect(AccentColorMode.current == .default)
        cleanUserDefaults()
    }

    @Test("SettingsViewModel.setAccentColorMode — state + UserDefaults sync")
    func setterSyncsState() {
        let vm = makeViewModel()
        #expect(vm.accentColorMode == .default)
        #expect(UserDefaults.standard.string(forKey: AccentColorMode.userDefaultsKey) == nil)

        vm.setAccentColorMode(.system)
        #expect(vm.accentColorMode == .system)
        #expect(UserDefaults.standard.string(forKey: AccentColorMode.userDefaultsKey) == "system")
        #expect(AccentColorMode.current == .system)

        vm.setAccentColorMode(.default)
        #expect(vm.accentColorMode == .default)
        #expect(UserDefaults.standard.string(forKey: AccentColorMode.userDefaultsKey) == "default")
        #expect(AccentColorMode.current == .default)

        cleanUserDefaults()
    }

    @Test("SettingsViewModel init — UserDefaults 기존 값 로드")
    func initLoadsPersistedMode() {
        cleanUserDefaults()
        UserDefaults.standard.set("system", forKey: AccentColorMode.userDefaultsKey)
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        let vm = SettingsViewModel(loginItemService: svc)
        #expect(vm.accentColorMode == .system)
        cleanUserDefaults()
    }

}
