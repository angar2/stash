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

    // TASK-099 다중 선택 붙여넣기 연결자 기본값 = 줄바꿈. 저장 형식이 *원문* 이라 두 글자 표기 `\n` 로 둔다
    // (설정 입력란에도 이 두 글자가 그대로 보이고, 실제 연결 시점에 개행으로 해석된다).
    static let multiPasteSeparatorDefault: String = "\\n"

    // TASK-099 혼합 계열 붙여넣기의 *묶음 사이* 지연 (파일 배열 → 텍스트). 앞 붙여넣기를 앱이 처리하기 전에
    // 다음 것이 클립보드를 덮어쓰면 *같은 내용이 두 번 붙거나 하나가 누락된다*.
    // 사용자 검수 fix-2 — 항목마다 합성하던 구조에서 계열별 2회로 줄이면서, 기다리는 횟수도 1회뿐이라
    // 220ms → 400ms 로 여유를 늘렸다(총 대기는 오히려 짧아진다). 실기 검수로 조정할 값이다.
    static let multiPasteSequentialDelay: Duration = .milliseconds(400)

    // TASK-098 — 핀 명칭(pin_alias) 길이 상한. 사이드바 최소 너비(180)에서 어차피 말줄임되므로 무제한 입력은 이득 없음.
    // 초과 입력은 차단하고 편집 중 글자 수(`n/40`)를 표시한다. DATA-MODEL §1 `pin_alias` 정책 정합.
    static let pinAliasMaxLength: Int = 40

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

    // TASK-054 클립 행 click vs drag 분리 임계 — mouseDown → mouseDragged 누적 거리 ≥ 5pt 시 윈도우 이동 진입.
    // macOS NSEvent 표준 정합 (시스템 click vs drag distinction 일반 5pt). UX-UI §4-3 본문 *클립 행 5pt threshold* 단일 진실.
    static let clipRowDragThreshold: CGFloat = 5

    // TASK-054 fix-1 popover width 영속 (사용자 freeform 변경 + 항상 영속).
    // UserDefaults 키 / cap 범위 — UX-UI §4-3 본문 단일 진실. 방식 1·2 공유 단일 키 (사용자 결정).
    static let popoverWidthMin: CGFloat = 280
    static let popoverWidthMax: CGFloat = 600

    // TASK-097 Pin 사이드바 너비 clamp 범위 + 항상 영속 — popoverWidth 정책 미러링.
    // 주의(TASK-097 검수 결과): 사이드바 패널은 `becomesKeyOnlyIfNeeded` + `orderFrontRegardless` 로 항상 non-key 라 styleMask `.resizable` 만으로는 *엣지 리사이즈 커서·드래그가 동작하지 않음*(실기 확인). 즉 현재 사용자 리사이즈 진입점은 없고, 본 상수·영속 인프라는 *저장 너비 복원* 경로에서만 실효. 사용자 조작 UX 는 별도 접근 필요.
    // 최소 180 = 타입 아이콘 + 본문 truncate 하한 / 최대 400 = popover 본체 압도 방지 상한. 기본값은 DesignTokens.WindowSize.pinSidebarWidth(220).
    static let pinSidebarWidthMin: CGFloat = 180
    static let pinSidebarWidthMax: CGFloat = 400

    // TASK-055 클립 상세 sub-window hover 트리거 임계.
    // 클립 행 위에 마우스 커서 본 시간 이상 머무름 → ClipsViewModel.triggerClipDetail() 자동 발화.
    // 같은 행 안 미세 움직임은 누적 보존 (hoverEnterRow 가 같은 row.id 추적 중이면 task 유지). 다른 행 이탈 시 cancel + 새 행 재시작.
    // UserDefaults 노출 X — 사용자 환경설정 영역 비공개. 향후 필요 시 코드 한 줄 수정으로 조정. FEATURES §3-8 단일 진실.
    // 2026-05-23 — 2.0 → 0.6 단축 (TASK-055 fix-3, 사용자 결정).
    static let clipDetailHoverDelaySeconds: TimeInterval = 0.6

    // TASK-079 — popover 상단 버튼 호버 툴팁 발화 지연. `.help()` 가 not-key panel 환경에서 미발화 → SwiftUI overlay 자체 구현으로 우회.
    // macOS 시스템 NSToolTip 표준 ~500-800ms 정합 — 0.8s 채택. 보조 안내성 툴팁이므로 의도적 호버 신호 필요 (clipDetailHoverDelaySeconds 0.6s 보다 약간 김 — 상세 sub-window 가 *정보 표시*이므로 빠른 진입이 합리적, 툴팁은 *보조 안내*).
    static let hoverTooltipDelaySeconds: TimeInterval = 0.8

    // UserDefaults 키 단일 진실 소스 — 모든 raw 문자열 키는 본 nested enum 안에 박힘. 호출처는 `UserDefaults.standard.<get/set>(forKey: Constants.UserDefaultsKeys.X)` 패턴.
    // *키 raw value 자체는 영구 불변* — 변경 시 기존 사용자 설정값 손실. enum case 이름·위치만 변경 자유.
    enum UserDefaultsKeys {
        // TASK-043 클립보드 수집 토글. ClipboardWatcher.enabled 초기값 + StatusItemController red dot indicator 추적.
        static let clipboardCaptureEnabled: String = "clipboardCaptureEnabled"

        // TASK-033 자동 paste 모드. ClipsViewModel.paste 의 effectiveMode 결정 (× accessibilityGranted).
        static let autoPasteEnabled: String = "autoPasteEnabled"

        // TASK-037 한 페이지 클립 수 (1~50).
        static let clipsPerPage: String = "clipsPerPage"

        // TASK-037 클립 리스트 높이 자동 조정.
        static let autoFitClipListHeight: String = "autoFitClipListHeight"

        // TASK-052 단축키 설명 표시.
        static let hintBarVisible: String = "hintBarVisible"

        // TASK-054 popover 진입 위치 + 드래그/리사이즈 — UX-UI §4-3 *보관함 오픈 위치* 영속. 5종 anchor enum raw 직렬화 + 영구 좌표 4종 (X/Y/Screen) + 토글 1종.
        static let popoverDefaultAnchor: String = "popoverDefaultAnchor"
        static let popoverRememberLastPosition: String = "popoverRememberLastPosition"
        static let popoverLastPositionX: String = "popoverLastPositionX"
        static let popoverLastPositionY: String = "popoverLastPositionY"
        static let popoverLastPositionScreenId: String = "popoverLastPositionScreenId"

        // TASK-054 fix-1 popover width 영속 — 사용자 freeform 변경 + 항상 영속.
        static let popoverWidth: String = "popoverWidth"

        // TASK-097 Pin 사이드바 width 영속 — 항상 영속 (위치 토글과 무관). 조회는 PopoverWindow.storedPinSidebarWidth.
        static let pinSidebarWidth: String = "pinSidebarWidth"

        // TASK-099 다중 선택 붙여넣기 *연결자* — 설정 일반 탭 자유 텍스트. 저장값은 **사용자가 입력한 원문**이며
        // `\n`·`\t` 두 글자 표기의 해석은 `MultiPasteComposer.resolveSeparator` 가 단일 지점에서 한다.
        // 빈 문자열은 미설정이 아니라 *구분 없이 연결* 이라는 유효한 값이다 (그래서 default fallback 은 키 부재로만 판정).
        static let multiPasteSeparator: String = "multiPasteSeparator"

        // TASK-098 설정 단축키 탭 묶음 접힘 상태 영속. 초기값 = 기본 단축키 열림 / PIN 단축키 닫힘.
        // (PIN 행이 2줄 구조라 함께 펼치면 탭 진입만으로 스크롤 발생 — UX-UI §4-4.)
        static let shortcutsBasicGroupExpanded: String = "shortcutsBasicGroupExpanded"
        static let shortcutsPinGroupExpanded: String = "shortcutsPinGroupExpanded"

        // FEATURES F-007 차단 앱 (Settings CollectionTab).
        static let blockedAppBundleIds: String = "blockedAppBundleIds"

        // PermissionToastNotifier — 권한 부여 첫 알림 1회 발화 추적.
        static let permissionGrantedNotified: String = "permissionGrantedNotified"

        // Onboarding 완료 영속 — 첫 실행 vs 재실행 분기. OnboardingViewModel.complete() 시점 true 박힘.
        static let hasCompletedOnboarding: String = "hasCompletedOnboarding"

        // Deprecated — 옛 키. 마이그레이션 전용 (SettingsViewModel.migrateLegacyPasteModeIfNeeded).
        enum Deprecated {
            // TASK-033 이전 PasteMode enum raw value 키. 현재는 autoPasteEnabled Bool 로 마이그레이션 완료.
            static let pasteMode: String = "pasteMode"
        }
    }

    // Notification.Name 단일 진실 소스 — 앱 내부 broadcast 이벤트.
    enum Notifications {
        // TASK-043 — ClipboardWatcher.enabled / red dot indicator 변경 시 StatusItemController 추종용.
        static let captureEnabledDidChange: Notification.Name = Notification.Name("stash.captureEnabledDidChange")

        // TASK-058 fix-1 — ClipboardWatcher insert 직후 post. ClipsViewModel 구독 → popover 떠있는 상태 (특히 유지 모드 ON) 에서 즉시 reload. 잠금 모드 도입 전에는 popover close → open 흐름으로 자연 reload 됐으나 유지 모드 ON 시 popover 미 close 라 알림 진입점 필요.
        static let clipboardDidInsertClip: Notification.Name = Notification.Name("stash.clipboardDidInsertClip")
    }

    // 변경 불가 단축키 keyCode (NSEvent 표준, UInt16 raw). PopoverPanel.PopoverHotkey + 기타 NSEvent 매칭 호출처가 단일 진실 소스로 참조.
    // macOS keyCode 표준 정합 — 영구 불변. enum 이름·구조만 정리 자유.
    enum KeyCodes {
        // 방향키 (`PopoverHotkey.moveSelectionUp` 외).
        static let arrowUp: UInt16 = 126
        static let arrowDown: UInt16 = 125

        // Return (일반) + Numpad Enter — TASK-051 `.confirm` 두 keyCode 동시 매칭.
        static let returnKey: UInt16 = 36
        static let numpadEnter: UInt16 = 76

        // ESC — `PopoverHotkey.escape` + ShortcutsTab.PopoverShortcutRecorder cancel.
        static let escape: UInt16 = 53

        // D — TASK-055 `.toggleClipDetail` (⌘+D).
        static let keyD: UInt16 = 2

        // Tab — TASK-044 PopoverPanel 안전망 (NSTextView insertTab: 차단).
        static let tab: UInt16 = 48

        // TASK-098 — 숫자 키 (Pin 직접 paste 단축키 기본값 `⌥⌘1`~`⌥⌘0`).
        // 주의: `kVK_ANSI_*` 숫자 keyCode 는 **순차가 아니다** — 5·6 이 23·22 로 뒤집혀 있고 7·8·9 는 26·28·25.
        // `18 + n` 같은 산술로 만들면 5·6 번이 서로 바뀐다. 반드시 본 표를 참조할 것.
        // index 0 = 숫자 1 … index 8 = 숫자 9 / index 9 = 숫자 0 (Pin 10번).
        static let digitsPinOrder: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    }
}
