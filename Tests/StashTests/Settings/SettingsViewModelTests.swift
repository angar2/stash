// SettingsViewModel 단위 테스트 — Login Item 토글 + Paste 모드 + 차단 앱 관리
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    private func makeViewModel() -> (SettingsViewModel, MockLoginItemRegistrar) {
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        // 테스트별 격리 — UserDefaults 키 클린
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        UserDefaults.standard.removeObject(forKey: "blockedAppBundleIds")
        return (SettingsViewModel(loginItemService: svc), reg)
    }

    @Test("Login Item 토글 — registrar 호출")
    func loginItemToggle() {
        let (vm, reg) = makeViewModel()
        vm.toggleLoginItem(true)
        #expect(vm.loginItemEnabled == true)
        #expect(reg.registerCallCount == 1)
        vm.toggleLoginItem(false)
        #expect(vm.loginItemEnabled == false)
        #expect(reg.unregisterCallCount == 1)
    }

    @Test("Paste 모드 변경 — UserDefaults 저장")
    func pasteModeChange() {
        let (vm, _) = makeViewModel()
        vm.setPasteMode(.copyBack)
        #expect(vm.pasteMode == .copyBack)
        #expect(UserDefaults.standard.string(forKey: "pasteMode") == "copyBack")
    }

    @Test("차단 앱 추가/제거 — 중복 방지")
    func blockedAppManagement() {
        let (vm, _) = makeViewModel()
        vm.addBlockedApp(bundleId: "com.example.app")
        #expect(vm.blockedAppBundleIds == ["com.example.app"])
        vm.addBlockedApp(bundleId: "com.example.app")  // 중복
        #expect(vm.blockedAppBundleIds.count == 1)
        vm.addBlockedApp(bundleId: "com.foo.bar")
        #expect(vm.blockedAppBundleIds.count == 2)
        vm.removeBlockedApp(bundleId: "com.example.app")
        #expect(vm.blockedAppBundleIds == ["com.foo.bar"])
    }
}
