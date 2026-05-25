// UserDefaults 키 raw value 불변 검증 — TASK-084 Phase 1 안전망
// 각 키의 string raw value 가 *변경 0* 임을 컴파일·테스트 단계에서 강제. 사용자 기존 설정값 보존 의무.
import Testing
@testable import stash

@Suite("Constants.UserDefaultsKeys raw value 불변")
struct UserDefaultsKeysTests {
    @Test("모든 키 raw value 가 옛 raw 문자열과 비트 단위 동일")
    func keyRawValuesUnchanged() {
        #expect(Constants.UserDefaultsKeys.clipboardCaptureEnabled == "clipboardCaptureEnabled")
        #expect(Constants.UserDefaultsKeys.autoPasteEnabled == "autoPasteEnabled")
        #expect(Constants.UserDefaultsKeys.clipsPerPage == "clipsPerPage")
        #expect(Constants.UserDefaultsKeys.autoFitClipListHeight == "autoFitClipListHeight")
        #expect(Constants.UserDefaultsKeys.hintBarVisible == "hintBarVisible")
        #expect(Constants.UserDefaultsKeys.popoverDefaultAnchor == "popoverDefaultAnchor")
        #expect(Constants.UserDefaultsKeys.popoverRememberLastPosition == "popoverRememberLastPosition")
        #expect(Constants.UserDefaultsKeys.popoverLastPositionX == "popoverLastPositionX")
        #expect(Constants.UserDefaultsKeys.popoverLastPositionY == "popoverLastPositionY")
        #expect(Constants.UserDefaultsKeys.popoverLastPositionScreenId == "popoverLastPositionScreenId")
        #expect(Constants.UserDefaultsKeys.popoverWidth == "popoverWidth")
        #expect(Constants.UserDefaultsKeys.blockedAppBundleIds == "blockedAppBundleIds")
        #expect(Constants.UserDefaultsKeys.permissionGrantedNotified == "permissionGrantedNotified")
        #expect(Constants.UserDefaultsKeys.hasCompletedOnboarding == "hasCompletedOnboarding")
        #expect(Constants.UserDefaultsKeys.Deprecated.pasteMode == "pasteMode")
    }

    @Test("모든 키 raw value 가 unique (Set 사이즈 = 키 개수)")
    func keyRawValuesUnique() {
        let keys: [String] = [
            Constants.UserDefaultsKeys.clipboardCaptureEnabled,
            Constants.UserDefaultsKeys.autoPasteEnabled,
            Constants.UserDefaultsKeys.clipsPerPage,
            Constants.UserDefaultsKeys.autoFitClipListHeight,
            Constants.UserDefaultsKeys.hintBarVisible,
            Constants.UserDefaultsKeys.popoverDefaultAnchor,
            Constants.UserDefaultsKeys.popoverRememberLastPosition,
            Constants.UserDefaultsKeys.popoverLastPositionX,
            Constants.UserDefaultsKeys.popoverLastPositionY,
            Constants.UserDefaultsKeys.popoverLastPositionScreenId,
            Constants.UserDefaultsKeys.popoverWidth,
            Constants.UserDefaultsKeys.blockedAppBundleIds,
            Constants.UserDefaultsKeys.permissionGrantedNotified,
            Constants.UserDefaultsKeys.hasCompletedOnboarding,
            Constants.UserDefaultsKeys.Deprecated.pasteMode
        ]
        #expect(Set(keys).count == keys.count)
    }
}

@Suite("Constants.Notifications raw value 불변")
struct NotificationsRawValueTests {
    @Test("Notification.Name raw value 가 옛 raw 문자열과 동일")
    func notificationNamesUnchanged() {
        #expect(Constants.Notifications.captureEnabledDidChange.rawValue == "stash.captureEnabledDidChange")
        #expect(Constants.Notifications.clipboardDidInsertClip.rawValue == "stash.clipboardDidInsertClip")
    }
}
