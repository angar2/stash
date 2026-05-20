// SettingsViewModel 단위 테스트 — Login Item 토글 + 바로 붙여넣기 토글 (TASK-033) + 저장하지 않을 앱 관리
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("SettingsViewModel", .serialized)
struct SettingsViewModelTests {
    private func makeViewModel(accessibilityGranted: Bool = true) -> (SettingsViewModel, MockLoginItemRegistrar) {
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        // 테스트별 격리 — UserDefaults 키 클린 (TASK-033 마이그레이션 영향 회피)
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        UserDefaults.standard.removeObject(forKey: "autoPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "blockedAppBundleIds")
        // TASK-037 — 디스플레이 환경설정 키 클린 + register defaults 재적용 (테스트 격리).
        UserDefaults.standard.removeObject(forKey: "clipsPerPage")
        UserDefaults.standard.removeObject(forKey: "autoFitClipListHeight")
        UserDefaults.standard.register(defaults: [
            "clipsPerPage": Constants.clipsPerPageDefault,
            "autoFitClipListHeight": false
        ])
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

    // MARK: - TASK-037 디스플레이 환경설정

    @Test("clipsPerPage 기본값 = Constants.clipsPerPageDefault (6)")
    func clipsPerPage_defaultIsSix() {
        let (vm, _) = makeViewModel()
        #expect(vm.clipsPerPage == Constants.clipsPerPageDefault)
        #expect(vm.clipsPerPage == 6)
    }

    @Test("clipsPerPage clamp — 1 미만 입력 시 1")
    func clipsPerPage_clampLowBoundary() {
        let (vm, _) = makeViewModel()
        vm.setClipsPerPage(0)
        #expect(vm.clipsPerPage == 1)
        vm.setClipsPerPage(-5)
        #expect(vm.clipsPerPage == 1)
    }

    @Test("clipsPerPage clamp — 50 초과 입력 시 50")
    func clipsPerPage_clampHighBoundary() {
        let (vm, _) = makeViewModel()
        vm.setClipsPerPage(75)
        #expect(vm.clipsPerPage == 50)
        vm.setClipsPerPage(10000)
        #expect(vm.clipsPerPage == 50)
    }

    @Test("clipsPerPage 라운드트립 — UserDefaults 저장 후 새 인스턴스에서 복원")
    func clipsPerPage_roundtrip() {
        let (vm1, _) = makeViewModel()
        vm1.setClipsPerPage(15)
        #expect(UserDefaults.standard.integer(forKey: "clipsPerPage") == 15)

        let reg2 = MockLoginItemRegistrar()
        let svc2 = LoginItemService(registrar: reg2)
        let vm2 = SettingsViewModel(loginItemService: svc2)
        #expect(vm2.clipsPerPage == 15)
    }

    @Test("autoFitClipListHeight 기본값 false")
    func autoFit_defaultIsFalse() {
        let (vm, _) = makeViewModel()
        #expect(vm.autoFitClipListHeight == false)
    }

    @Test("autoFitClipListHeight 라운드트립 — UserDefaults 저장 후 새 인스턴스에서 복원")
    func autoFit_roundtrip() {
        let (vm1, _) = makeViewModel()
        vm1.setAutoFitClipListHeight(true)
        #expect(UserDefaults.standard.bool(forKey: "autoFitClipListHeight") == true)

        let reg2 = MockLoginItemRegistrar()
        let svc2 = LoginItemService(registrar: reg2)
        let vm2 = SettingsViewModel(loginItemService: svc2)
        #expect(vm2.autoFitClipListHeight == true)
    }
}
