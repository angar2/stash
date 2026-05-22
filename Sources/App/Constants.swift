// 앱 전역 상수 단일 위치 — 서비스 로직 안 하드코딩 금지
import Foundation

enum Constants {
    // F-001 클립보드 폴링
    static let clipboardPollingInterval: Duration = .milliseconds(500)

    // F-007 호출 모델 임계값 — ⌘ hold 영역 (TASK-018 Phase 9 v1.0 보류)
    // TASK-018 Phase 6 — hold 200ms → 500ms. 단순 ⌘+key 단축키 조합(⌘C/V/Z 등) 시 사용자가 ⌘를 잠깐 더 누르고 있어도 popover 발동되던 오트리거 방지.
    // TASK-046 — ⌘ double-tap 트리거 폐기로 관련 상수 (`modifierDoubleTapInterval` / `hotkeyDoubleTapIntervalSeconds`) 제거. hold 상수만 잔존.
    static let modifierHoldThreshold: Duration = .milliseconds(500)
    // HotkeyMonitor — NSEvent 글로벌 modifier hold 감지 (TimeInterval 형식, DispatchQueue async 용)
    static let hotkeyHoldThresholdSeconds: TimeInterval = 0.5

    // F-004 Pin 한도
    static let maxPinnedClips: Int = 10

    // F-002 + SERVICE-POLICY §3 LRU
    static let maxUnpinnedClips: Int = 200

    // SERVICE-POLICY §4 파일 클립
    static let fileClipCopyMaxSize: Int = 100 * 1024 * 1024  // 100MB

    // SERVICE-POLICY §4-4 다중 파일 묶음 (TASK-026) — 1 row 임계
    static let maxMultiFileEntries: Int = 100

    // UX-UI §6 메뉴바 인라인 토스트
    static let toastAutoDismiss: Duration = .milliseconds(3000)

    // UX-UI §3 onboarding 권한 polling
    static let permissionPollingIntervalOnboarding: Duration = .milliseconds(1000)

    // F-009 검색 debounce
    static let searchDebounce: Duration = .milliseconds(100)

    // F-004 Pin 사이드 메뉴 펼침 지연
    static let pinSideMenuExpandDelay: Duration = .milliseconds(200)

    // TASK-023 이미지 파일 확장자 화이트리스트 — Finder file URL 분류 시 .image / .file 분기에 사용.
    // 소문자 비교 (대소문자 무관 매칭은 lowercased 변환 후 lookup).
    static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "heif", "webp"
    ]

    // TASK-037 디스플레이 탭 — 한 번에 보이는 클립 수 N (사용자 환경설정).
    // default 6 = TASK-036 토큰 추정값 (clipListMaxHeight 276 ÷ rowMinHeight 44) 인계.
    // 범위 1~50. 화면 높이 초과 시 effectiveClipListHeight 가 자동 cap.
    // floor=3 (autoFit ON 시 최소 컨테이너 행 수). 단 N<3 시 floor=N.
    static let clipsPerPageDefault: Int = 6
    static let clipsPerPageMin: Int = 1
    static let clipsPerPageMax: Int = 50
    static let clipListAutoFitFloor: Int = 3

    // TASK-043 클립보드 수집 토글 — UserDefaults 키. ClipboardWatcher.enabled 초기값 + StatusItemController red dot indicator 추적.
    static let clipboardCaptureEnabledKey: String = "clipboardCaptureEnabled"

    // TASK-043 — ClipboardWatcher.enabled / red dot indicator 변경 시 StatusItemController 추종용 NotificationCenter 이름.
    static let captureEnabledDidChangeNotification: Notification.Name = Notification.Name("stash.captureEnabledDidChange")
}
