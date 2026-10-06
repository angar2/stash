// AccessibilityPermissionChecker protocol 준수 — AXIsProcessTrustedWithOptions thin wrapper
import ApplicationServices
#if APP_STORE
import CoreGraphics
import IOKit.hidsystem
import OSLog
#endif

struct AXPermissionChecker: AccessibilityPermissionChecker {
    func isTrusted(promptUserIfNeeded: Bool) -> Bool {
        #if APP_STORE
        // TASK-113 — 샌드박스 앱은 손쉬운 사용 신뢰 프롬프트를 띄울 수 없다. 요청은 `requestPostEventAccess()` 가 맡고
        // 여기서는 상태만 읽는다. 판정 규칙은 `SandboxPermissionDecision` 주석 참조.
        if promptUserIfNeeded { Self.requestPostEventAccess() }
        let axTrusted = AXIsProcessTrusted()
        let preflight = CGPreflightPostEventAccess()
        Self.logIfChanged(axTrusted: axTrusted, preflight: preflight)
        return SandboxPermissionDecision.isGranted(axTrusted: axTrusted, postEventPreflight: preflight)
        #else
        // "AXTrustedCheckOptionPrompt" = kAXTrustedCheckOptionPrompt raw value
        let options = ["AXTrustedCheckOptionPrompt": promptUserIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #endif
    }

    #if APP_STORE
    /// 이벤트 게시 권한 요청 — 앱을 시스템 설정 *손쉬운 사용* 목록에 올린다 (Apple DTS 가 샌드박스 호환이라고 밝힌 경로).
    /// 사용자가 설정을 여는 버튼(온보딩 *시스템 환경설정 열기* · 설정 일반 탭 *시스템 접근 권한*)을 누를 때 부른다.
    /// 이미 허용이면 아무것도 하지 않는다. 반환값은 캐시된 값이라 판정에 쓰지 않는다.
    static func requestPostEventAccess() {
        guard !CGPreflightPostEventAccess() else { return }
        let result = CGRequestPostEventAccess()
        Logger.permission.info("PostEvent 권한 요청 — result=\(result)")
    }

    /// 마지막으로 남긴 세 값. 1초 폴링마다 같은 줄을 남기지 않으려고 바뀔 때만 기록한다.
    /// `nonisolated(unsafe)` 사유: PermissionService actor 안에서만 읽고 쓴다.
    nonisolated(unsafe) private static var lastLogged: (Bool, Bool, Bool)?

    /// `IOHIDCheckAccess(PostEvent)` 는 판정에 쓰지 않는다. 실행 중 갱신되는지 확인되지 않아 로그로만 남겨 참고한다 (조사 02).
    private static func logIfChanged(axTrusted: Bool, preflight: Bool) {
        let hidGranted = IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
        let current = (axTrusted, preflight, hidGranted)
        if let last = lastLogged, last == current { return }
        lastLogged = current
        Logger.permission.info("Sandbox 권한 값 — axTrusted=\(axTrusted), postEventPreflight=\(preflight), hidPostEvent=\(hidGranted)")
    }
    #endif
}
