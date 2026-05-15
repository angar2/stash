// 앱 전역 상수 단일 위치 — 서비스 로직 안 하드코딩 금지
import Foundation

enum Constants {
    // F-001 클립보드 폴링
    static let clipboardPollingInterval: Duration = .milliseconds(500)

    // F-007 호출 모델 임계값
    // TASK-018 Phase 6 — hold 200ms → 500ms. 단순 ⌘+key 단축키 조합(⌘C/V/Z 등) 시 사용자가 ⌘를 잠깐 더 누르고 있어도 popover 발동되던 오트리거 방지.
    static let modifierHoldThreshold: Duration = .milliseconds(500)
    static let modifierDoubleTapInterval: Duration = .milliseconds(300)
    // HotkeyMonitor — NSEvent 글로벌 modifier 감지 (TimeInterval 형식, DispatchQueue async 용)
    static let hotkeyHoldThresholdSeconds: TimeInterval = 0.5
    static let hotkeyDoubleTapIntervalSeconds: TimeInterval = 0.25

    // F-004 Pin 한도
    static let maxPinnedClips: Int = 10

    // F-002 + SERVICE-POLICY §3 LRU
    static let maxUnpinnedClips: Int = 200

    // SERVICE-POLICY §4 파일 클립
    static let fileClipCopyMaxSize: Int = 100 * 1024 * 1024  // 100MB

    // UX-UI §6 메뉴바 인라인 토스트
    static let toastAutoDismiss: Duration = .milliseconds(3000)

    // UX-UI §3 onboarding 권한 polling
    static let permissionPollingIntervalOnboarding: Duration = .milliseconds(1000)

    // F-009 검색 debounce
    static let searchDebounce: Duration = .milliseconds(100)

    // F-004 Pin 사이드 메뉴 펼침 지연
    static let pinSideMenuExpandDelay: Duration = .milliseconds(200)
}
