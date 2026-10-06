// AXIsProcessTrustedWithOptions 추상화 protocol
import Foundation

protocol AccessibilityPermissionChecker: Sendable {
    /// 현재 Accessibility 권한 상태.
    /// - Parameter promptUserIfNeeded: true 면 시스템 권한 요청 다이얼로그 표시.
    func isTrusted(promptUserIfNeeded: Bool) -> Bool
}

/// TASK-113 — App Store판(샌드박스) 붙여넣기 권한 판정 규칙. 판에 상관없이 컴파일해 코드 테스트로 확인한다.
///
/// 샌드박스 앱의 ⌘V 합성에 필요한 것은 이벤트 게시(PostEvent) 권한이다. 그런데 그 확인 값(`CGPreflightPostEventAccess`)은
/// 실행 중인 프로세스 안에서 갱신되지 않아, 사용자가 켠 뒤에도 재실행 전까지 거부로 읽힌다(플랜 007 발견 1).
/// 같은 순간 `AXIsProcessTrusted` 는 즉시 바뀌므로 화면 반영은 이 값으로 하고, 이 값이 샌드박스에서 늘 거짓인 환경이
/// 있어도 재실행하면 허용으로 읽히도록 두 값 중 하나라도 허용이면 허용으로 본다.
enum SandboxPermissionDecision {
    static func isGranted(axTrusted: Bool, postEventPreflight: Bool) -> Bool {
        axTrusted || postEventPreflight
    }
}
