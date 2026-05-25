// SettingsViewModel popover 위치 (보관함 오픈 위치) 설정 단위 테스트 (TASK-054)
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("SettingsViewModel popover 위치 (TASK-054)", .serialized)
struct SettingsViewModelPopoverPositionTests {

    private func makeViewModel() -> SettingsViewModel {
        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        // 격리 — TASK-054 신규 키 + 기존 디스플레이 키 모두 클린.
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverLastPositionX)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverLastPositionY)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverLastPositionScreenId)
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        UserDefaults.standard.removeObject(forKey: "autoPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "blockedAppBundleIds")
        UserDefaults.standard.removeObject(forKey: "clipsPerPage")
        UserDefaults.standard.removeObject(forKey: "autoFitClipListHeight")
        UserDefaults.standard.removeObject(forKey: "hintBarVisible")
        UserDefaults.standard.register(defaults: [
            "clipsPerPage": Constants.clipsPerPageDefault,
            "autoFitClipListHeight": false,
            "hintBarVisible": true
        ])
        return SettingsViewModel(loginItemService: svc)
    }

    @Test("TASK-065 — default 값 (UserDefaults 미설정 시) = .topRight + false")
    func defaultValues() {
        let vm = makeViewModel()
        #expect(vm.popoverDefaultAnchor == .topRight)
        #expect(vm.popoverRememberLastPosition == false)
    }

    @Test("TASK-054 — setPopoverDefaultAnchor(.center) → state + UserDefaults 동기")
    func setDefaultAnchor() {
        let vm = makeViewModel()
        vm.setPopoverDefaultAnchor(.center)
        #expect(vm.popoverDefaultAnchor == .center)
        #expect(UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor) == "center")
    }

    @Test("TASK-054 — setPopoverDefaultAnchor 5종 anchor 모두 정합")
    func setAllAnchors() {
        let vm = makeViewModel()
        for anchor in PopoverAnchor.allCases {
            vm.setPopoverDefaultAnchor(anchor)
            #expect(vm.popoverDefaultAnchor == anchor)
            #expect(UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor) == anchor.rawValue)
        }
    }

    @Test("TASK-054 — setPopoverRememberLastPosition(true) → state + UserDefaults 동기")
    func setRememberOn() {
        let vm = makeViewModel()
        vm.setPopoverRememberLastPosition(true)
        #expect(vm.popoverRememberLastPosition == true)
        #expect(UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition) == true)
    }

    @Test("TASK-054 — setPopoverRememberLastPosition(false) → 저장 좌표 키 제거")
    func setRememberOffPurgesSavedOrigin() {
        let vm = makeViewModel()
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition)
        UserDefaults.standard.set(100.0, forKey: Constants.UserDefaultsKeys.popoverLastPositionX)
        UserDefaults.standard.set(200.0, forKey: Constants.UserDefaultsKeys.popoverLastPositionY)
        UserDefaults.standard.set("Display1", forKey: Constants.UserDefaultsKeys.popoverLastPositionScreenId)

        vm.setPopoverRememberLastPosition(false)

        #expect(vm.popoverRememberLastPosition == false)
        #expect(UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition) == false)
        #expect(UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.popoverLastPositionX) == nil)
        #expect(UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.popoverLastPositionY) == nil)
        #expect(UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.popoverLastPositionScreenId) == nil)
    }

    @Test("TASK-054 — loadDisplayPreferences (init 안 호출) → UserDefaults 값 박혀있으면 그 값 반영")
    func loadPersistedValues() {
        UserDefaults.standard.set("center", forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor)
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition)
        UserDefaults.standard.set(Constants.clipsPerPageDefault, forKey: "clipsPerPage")

        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        let vm = SettingsViewModel(loginItemService: svc)

        #expect(vm.popoverDefaultAnchor == .center)
        #expect(vm.popoverRememberLastPosition == true)

        // 클린업
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition)
    }

    @Test("TASK-065 — loadDisplayPreferences 잘못된 anchor raw → fallback .topRight (default 변경 정합)")
    func loadInvalidAnchorFallback() {
        UserDefaults.standard.set("invalid_anchor", forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor)

        let reg = MockLoginItemRegistrar()
        let svc = LoginItemService(registrar: reg)
        let vm = SettingsViewModel(loginItemService: svc)

        #expect(vm.popoverDefaultAnchor == .topRight, "잘못된 raw → default fallback")

        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor)
    }

    // TASK-054 fix-1 — clipsPerPageDeltaRequest notification 폐기 (시스템 표준 NSWindow resize 위임).
    // PopoverWindow.windowWillResize 가 SettingsViewModel.setClipsPerPage 직접 호출 — 본 ViewModel 단위 테스트 범위 X.
    // setClipsPerPage 본체 동작은 기존 `SettingsViewModelTests` 가 검증.
}
