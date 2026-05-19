// SettingsViewModel 단위 테스트 — Login Item 토글 + 바로 붙여넣기 토글 (TASK-033) + 저장하지 않을 앱 관리
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    private func makeViewModel(accessibilityGranted: Bool = true) -> (SettingsViewModel, MockLoginItemRegistrar) {
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        // 테스트별 격리 — UserDefaults 키 클린 (TASK-033 마이그레이션 영향 회피)
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        UserDefaults.standard.removeObject(forKey: "autoPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "blockedAppBundleIds")
        let vm = SettingsViewModel(loginItemService: svc)
        vm.accessibilityGranted = accessibilityGranted
        return (vm, reg)
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

    @Test("autoPasteEnabled 토글 — UserDefaults 저장")
    func autoPasteToggle() {
        let (vm, _) = makeViewModel(accessibilityGranted: true)
        vm.setAutoPasteEnabled(false)
        #expect(vm.autoPasteEnabled == false)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == false)
        vm.setAutoPasteEnabled(true)
        #expect(vm.autoPasteEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == true)
    }

    @Test("autoPasteEnabled — 권한 X 시 ON 시도 차단")
    func autoPasteBlockedWithoutPermission() {
        let (vm, _) = makeViewModel(accessibilityGranted: false)
        let prev = vm.autoPasteEnabled
        vm.setAutoPasteEnabled(true)
        // 권한 X 시 setAutoPasteEnabled(true) 안전망 — 변경 X
        #expect(vm.autoPasteEnabled == prev)
    }

    @Test("저장하지 않을 앱 추가/삭제 — 중복 방지")
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
