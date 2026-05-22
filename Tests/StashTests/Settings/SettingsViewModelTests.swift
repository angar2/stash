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
        // TASK-037 / TASK-052 — 디스플레이 환경설정 키 클린 + register defaults 재적용 (테스트 격리).
        UserDefaults.standard.removeObject(forKey: "clipsPerPage")
        UserDefaults.standard.removeObject(forKey: "autoFitClipListHeight")
        UserDefaults.standard.removeObject(forKey: "hintBarVisible")
        UserDefaults.standard.register(defaults: [
            "clipsPerPage": Constants.clipsPerPageDefault,
            "autoFitClipListHeight": false,
            "hintBarVisible": true
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

    // MARK: - TASK-047 권한 변동 시 autoPasteEnabled 대칭 정합

    @Test("TASK-047 — 권한 X→O 회복 시 autoPasteEnabled 자동 ON + UserDefaults 저장")
    func permissionGranted_autoPasteAutoOn() {
        let (vm, _) = makeViewModel(accessibilityGranted: false)
        vm.autoPasteEnabled = false
        UserDefaults.standard.set(false, forKey: "autoPasteEnabled")

        vm.updateAccessibilityGranted(true)

        #expect(vm.accessibilityGranted == true)
        #expect(vm.autoPasteEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == true)
    }

    @Test("TASK-047 — 권한 X→O 회복 시 autoPasteEnabled 이미 true 면 멱등 (UserDefaults set skip)")
    func permissionGranted_autoPasteAlreadyOn_idempotent() {
        let (vm, _) = makeViewModel(accessibilityGranted: false)
        vm.autoPasteEnabled = true
        // 멱등 가드 검증 — UserDefaults 명시 false 박음 → set skip 되어야 false 유지. 가드 깨지면 true 로 덮어쓰여짐.
        UserDefaults.standard.set(false, forKey: "autoPasteEnabled")

        vm.updateAccessibilityGranted(true)

        #expect(vm.accessibilityGranted == true)
        #expect(vm.autoPasteEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == false)
    }

    @Test("TASK-047 — 권한 O→X 회수 시 autoPasteEnabled 자동 OFF + UserDefaults 저장")
    func permissionRevoked_autoPasteForcedOff() {
        let (vm, _) = makeViewModel(accessibilityGranted: true)
        vm.autoPasteEnabled = true
        UserDefaults.standard.set(true, forKey: "autoPasteEnabled")

        vm.updateAccessibilityGranted(false)

        #expect(vm.accessibilityGranted == false)
        #expect(vm.autoPasteEnabled == false)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == false)
    }

    @Test("TASK-047 — 권한 동일값 호출은 멱등 (prev == granted 가드)")
    func permissionSameValue_noop() {
        let (vm, _) = makeViewModel(accessibilityGranted: true)
        vm.autoPasteEnabled = true
        UserDefaults.standard.set(true, forKey: "autoPasteEnabled")

        vm.updateAccessibilityGranted(true)

        #expect(vm.accessibilityGranted == true)
        #expect(vm.autoPasteEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == true)
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

    // MARK: - TASK-052 단축키 설명 표시 토글

    @Test("TASK-052 — hintBarVisible 기본값 true (register defaults 의존)")
    func hintBarVisible_defaultIsTrue() {
        let (vm, _) = makeViewModel()
        #expect(vm.hintBarVisible == true)
    }

    @Test("TASK-052 — setHintBarVisible(false) → state + UserDefaults 갱신")
    func hintBarVisible_setFalse() {
        let (vm, _) = makeViewModel()
        vm.setHintBarVisible(false)
        #expect(vm.hintBarVisible == false)
        #expect(UserDefaults.standard.bool(forKey: "hintBarVisible") == false)
    }

    @Test("TASK-052 — setHintBarVisible(true) 복원 → state + UserDefaults 갱신")
    func hintBarVisible_setTrue() {
        let (vm, _) = makeViewModel()
        vm.setHintBarVisible(false)
        vm.setHintBarVisible(true)
        #expect(vm.hintBarVisible == true)
        #expect(UserDefaults.standard.bool(forKey: "hintBarVisible") == true)
    }

    @Test("TASK-052 — hintBarVisible 라운드트립 — UserDefaults 저장 후 새 인스턴스에서 복원")
    func hintBarVisible_roundtrip() {
        let (vm1, _) = makeViewModel()
        vm1.setHintBarVisible(false)
        #expect(UserDefaults.standard.bool(forKey: "hintBarVisible") == false)

        let reg2 = MockLoginItemRegistrar()
        let svc2 = LoginItemService(registrar: reg2)
        let vm2 = SettingsViewModel(loginItemService: svc2)
        #expect(vm2.hintBarVisible == false)
    }
    // 비고 (TASK-052): notification (displayLayoutDidChange) 발행 자체는 별도 단위 검증 X — 인접 setter (`setAutoFitClipListHeight` / `setClipsPerPage`) 도 동일 notification 발행하지만 발행 횟수 자체는 검증 X (NotificationCenter 격리 비용 + 다른 suite 와의 cross-talk). 발행 흐름은 수동 시나리오 (popover open 상태 토글 → height 즉시 변동) 가 단일 진실 가드.
}
