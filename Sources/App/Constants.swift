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
    // TASK-061 — 100ms → 200ms 조정. 100ms 는 사용자 평균 타이핑 간격보다 짧아 *타이핑 도중* 매번 발화. 200ms 는 타이핑 정지 0.2초 후 1회 발화 — 빠른 결과 박힘 + 타이핑 중 외곽 변동 차단 균형.
    static let searchDebounce: Duration = .milliseconds(200)

    // TASK-061 — 검색 max wait. 디바운스 단독 시 사용자 200ms 미만 간격 연속 타이핑 시 *완전히 다 작성할 때까지* 결과 안 박힘. max wait 박으면 첫 schedule 후 500ms 도달 시 강제 fire → 사용자 빠른 타이핑 중에도 *500ms 마다 결과 박힘*. RxJS/Lodash `debounce({ maxWait: ... })` 표준 패턴.
    static let searchMaxWait: Duration = .milliseconds(500)

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
    // TASK-061 — `clipListAutoFitFloor` (floor=3) 폐기. autoFit ON 시 visibleCount 자연 그대로 변동 — 검색 진행 중 결과 변동 시 사용자 인지 *3행 사이즈 고정 oscillation* 차단.
    static let clipsPerPageDefault: Int = 6
    static let clipsPerPageMin: Int = 1
    static let clipsPerPageMax: Int = 50

    // TASK-043 클립보드 수집 토글 — UserDefaults 키. ClipboardWatcher.enabled 초기값 + StatusItemController red dot indicator 추적.
    static let clipboardCaptureEnabledKey: String = "clipboardCaptureEnabled"

    // TASK-043 — ClipboardWatcher.enabled / red dot indicator 변경 시 StatusItemController 추종용 NotificationCenter 이름.
    static let captureEnabledDidChangeNotification: Notification.Name = Notification.Name("stash.captureEnabledDidChange")

    // TASK-058 fix-1 — ClipboardWatcher insert 직후 post. ClipsViewModel 구독 → popover 떠있는 상태 (특히 유지 모드 ON) 에서 즉시 reload. 잠금 모드 도입 전에는 popover close → open 흐름으로 자연 reload 됐으나 유지 모드 ON 시 popover 미 close 라 알림 진입점 필요.
    static let clipboardDidInsertClipNotification: Notification.Name = Notification.Name("stash.clipboardDidInsertClip")

    // TASK-054 popover 진입 위치 + 드래그/리사이즈 — UX-UI §4-3 *보관함 오픈 위치* 영속.
    // 5종 anchor enum raw 직렬화 + 영구 좌표 4종 (X/Y/Screen) + 토글 1종.
    static let popoverDefaultAnchorKey: String = "popoverDefaultAnchor"
    static let popoverRememberLastPositionKey: String = "popoverRememberLastPosition"
    static let popoverLastPositionXKey: String = "popoverLastPositionX"
    static let popoverLastPositionYKey: String = "popoverLastPositionY"
    static let popoverLastPositionScreenIdKey: String = "popoverLastPositionScreenId"

    // TASK-054 클립 행 click vs drag 분리 임계 — mouseDown → mouseDragged 누적 거리 ≥ 5pt 시 윈도우 이동 진입.
    // macOS NSEvent 표준 정합 (시스템 click vs drag distinction 일반 5pt). UX-UI §4-3 본문 *클립 행 5pt threshold* 단일 진실.
    static let clipRowDragThreshold: CGFloat = 5

    // TASK-054 fix-1 popover width 영속 (사용자 freeform 변경 + 항상 영속).
    // UserDefaults 키 / cap 범위 — UX-UI §4-3 본문 단일 진실. 방식 1·2 공유 단일 키 (사용자 결정).
    static let popoverWidthKey: String = "popoverWidth"
    static let popoverWidthMin: CGFloat = 280
    static let popoverWidthMax: CGFloat = 600

    // TASK-055 클립 상세 sub-window hover 트리거 임계.
    // 클립 행 위에 마우스 커서 본 시간 이상 머무름 → ClipsViewModel.triggerClipDetail() 자동 발화.
    // 같은 행 안 미세 움직임은 누적 보존 (hoverEnterRow 가 같은 row.id 추적 중이면 task 유지). 다른 행 이탈 시 cancel + 새 행 재시작.
    // UserDefaults 노출 X — 사용자 환경설정 영역 비공개. 향후 필요 시 코드 한 줄 수정으로 조정. FEATURES §3-8 단일 진실.
    // 2026-05-23 — 2.0 → 0.6 단축 (TASK-055 fix-3, 사용자 결정).
    static let clipDetailHoverDelaySeconds: TimeInterval = 0.6

    // TASK-079 — popover 상단 버튼 호버 툴팁 발화 지연. `.help()` 가 not-key panel 환경에서 미발화 → SwiftUI overlay 자체 구현으로 우회.
    // macOS 시스템 NSToolTip 표준 ~500-800ms 정합 — 0.8s 채택. 보조 안내성 툴팁이므로 의도적 호버 신호 필요 (clipDetailHoverDelaySeconds 0.6s 보다 약간 김 — 상세 sub-window 가 *정보 표시*이므로 빠른 진입이 합리적, 툴팁은 *보조 안내*).
    static let hoverTooltipDelaySeconds: TimeInterval = 0.8
}
