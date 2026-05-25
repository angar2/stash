// Method1/2/3 공통 NSPanel + NSVisualEffectView setup 헬퍼 (UI Layer 중복 제거)
import AppKit
import SwiftUI
import OSLog

/// popover 안 단축키 정의 — 단일 진실 소스 (TASK-017 / TASK-021 / TASK-025 / TASK-033 fix-2 / TASK-036).
/// 변경 가능 6종 (togglePin / togglePinSidebar / deleteOne / deleteAll / copy / paste) 은 PopoverShortcutStore (자체 UserDefaults storage) 동적 조회 — SPM `setShortcut` 의 Carbon 글로벌 hotkey 등록 회피 (⌘V/⌘C 같은 시스템 표준 키 매핑 시 시스템 paste/copy 무력화 방지).
/// 변경 불가 (방향키/ESC/⌘+방향키/⌘+⇧+방향키) 는 hardcoded keyCode + modifiers.
/// PopoverPanel.installKeyDownHandler / installPopoverKeyEventMonitor 가 본 enum을 순회 매칭 → dispatch 분기.
enum PopoverHotkey: CaseIterable {
    case moveSelectionUp        // ↑ 단독 (TASK-021, 변경 불가)
    case moveSelectionDown      // ↓ 단독 (TASK-021, 변경 불가)
    case pageUp                 // ⌘+↑ (TASK-036, 변경 불가 — 페이지 점프, 가시 행 수만큼)
    case pageDown               // ⌘+↓ (TASK-036, 변경 불가 — 페이지 점프)
    case moveSelectionToFirst   // ⌘+⇧+↑ (TASK-036, 변경 불가 — 양 끝 점프 Home)
    case moveSelectionToLast    // ⌘+⇧+↓ (TASK-036, 변경 불가 — 양 끝 점프 End)
    case togglePin              // ⌘+P default (TASK-033 fix-2 — PopoverShortcutID.pinToggle 동적 조회)
    case togglePinSidebar       // ⌘+B default (TASK-033 fix-2 — PopoverShortcutID.pinSidebarToggle)
    case deleteOne              // ⌘+⌫ default (TASK-033 fix-2 — .deleteOne)
    case deleteAll              // ⌥+⌘+⌫ default (TASK-033 fix-2 — .deleteAll)
    case copy                   // ⌘+C default (TASK-033 fix-2 — .copy. 항상 .copyBack 호출, 권한 무관 활성)
    case paste                  // ⌘+V default (TASK-033 fix-2 — .paste. Accessibility 권한 게이트 조건부 활성)
    case confirm                // Enter 단독 (TASK-051, 변경 불가 — 일반 Return keyCode 36 + Numpad Enter keyCode 76 동시 매칭. autoPasteEnabled 분기 paste/copy 라우팅. IME marked text 시 monitor 가 forward)
    case escape                 // ESC 단독 (변경 불가 — macOS 표준 닫기/취소)
    case toggleClipDetail       // ⌘+D (TASK-055, 변경 불가 — 활성 클립 상세 sub-window toggle. NSTextField field editor 기본 키바인딩 충돌 X. PopoverShortcut defaults 비충돌)

    /// TASK-033 fix-2 — 변경 가능 단축키의 PopoverShortcutStore ID 매핑. 변경 불가 (방향키/ESC/⌘+방향키/⌘+⇧+방향키) 는 nil 반환 (hardcoded keyCode/modifiers 사용).
    var popoverShortcutID: PopoverShortcutID? {
        switch self {
        case .copy: return .copy
        case .paste: return .paste
        case .togglePin: return .pinToggle
        case .togglePinSidebar: return .pinSidebarToggle
        case .deleteOne: return .deleteOne
        case .deleteAll: return .deleteAll
        case .moveSelectionUp, .moveSelectionDown, .pageUp, .pageDown, .moveSelectionToFirst, .moveSelectionToLast, .confirm, .escape, .toggleClipDetail: return nil
        }
    }

    /// 변경 불가 단축키만 사용하는 hardcoded keyCode (NSEvent.keyCode raw 값).
    /// TASK-051 — `.confirm` 은 일반 Return 36 + Numpad Enter 76 둘 다 매칭하므로 본 프로퍼티는 *primary* (36) 반환. matches(event:) 분기에서 76 도 함께 검사.
    var keyCode: UInt16 {
        switch self {
        case .moveSelectionUp, .pageUp, .moveSelectionToFirst: return 126        // ↑ (단독 / ⌘+↑ / ⌘+⇧+↑)
        case .moveSelectionDown, .pageDown, .moveSelectionToLast: return 125     // ↓ (단독 / ⌘+↓ / ⌘+⇧+↓)
        case .confirm: return 36                                                 // Return (primary — matches(event:) 가 Numpad 76 도 함께 검사)
        case .escape: return 53                                                  // ESC
        case .toggleClipDetail: return 2                                         // D (TASK-055 — ⌘+D)
        case .togglePin, .togglePinSidebar, .deleteOne, .deleteAll, .copy, .paste: return 0  // PopoverShortcutStore 동적 조회
        }
    }

    /// 변경 불가 단축키만 사용하는 hardcoded modifiers.
    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .moveSelectionUp, .moveSelectionDown, .confirm, .escape: return []
        case .pageUp, .pageDown: return [.command]                              // TASK-036 — ⌘+↑/⌘+↓ 페이지 점프
        case .moveSelectionToFirst, .moveSelectionToLast: return [.command, .shift]  // TASK-036 — ⌘+⇧+↑/⌘+⇧+↓ 양 끝 점프
        case .toggleClipDetail: return [.command]                               // TASK-055 — ⌘+D
        case .togglePin, .togglePinSidebar, .deleteOne, .deleteAll, .copy, .paste: return []  // PopoverShortcutStore 동적 조회
        }
    }

    /// event 매칭. 변경 가능 단축키 → PopoverShortcutStore 동적 조회. 변경 불가 → hardcoded.
    /// TASK-051 — `.confirm` 만 keyCode 2종 (일반 Return 36 + Numpad Enter 76) 동시 매칭 분기. 다른 case 는 단일 keyCode 패턴 유지.
    func matches(event: NSEvent) -> Bool {
        if let id = popoverShortcutID {
            // PopoverShortcutStore 조회 → 사용자 변경값 또는 default 반환. nil 이면 매칭 X.
            guard let shortcut = PopoverShortcutStore.get(id) else { return false }
            return shortcut.matches(event: event)
        }
        let meaningful: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        // TASK-051 — `.confirm` 은 일반 Return (36) + Numpad Enter (76) 둘 다 매칭.
        if self == .confirm {
            guard event.keyCode == 36 || event.keyCode == 76 else { return false }
            return event.modifierFlags.intersection(meaningful) == modifiers
        }
        // 변경 불가 (방향키/ESC) — hardcoded 단일 keyCode
        guard event.keyCode == keyCode else { return false }
        return event.modifierFlags.intersection(meaningful) == modifiers
    }
}

@MainActor
enum PopoverPanel {
    /// borderless KeyablePanel + contentView=NSVisualEffectView (Liquid Glass 표준 패턴)
    /// TASK-054 fix-1 — styleMask 에 `.resizable` 추가 — macOS 시스템 표준 NSWindow resize 위임. 4 edges + 4 코너 자동 hit-test + cursor.
    /// borderless + resizable 조합은 시각 resize 핸들 없음 (cursor 변경만). NSWindowDelegate.windowWillResize 가 width clamp + height 1행 snap 책임.
    static func make(width: CGFloat, height: CGFloat) -> (panel: KeyablePanel, visualEffectView: NSVisualEffectView) {
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        let p = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        // TASK-070 — 시스템 표준 윈도우 시각 (titled + fullSizeContentView + titlebarAppearsTransparent + titleVisibility=.hidden). 시스템 자체 둥근 corner + 보더 + 그림자 박음 (corner radius 영역 밖 각진 잔존 차단). titlebar button 3종 hidden.
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.title = ""
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isMovableByWindowBackground = true
        // TASK-037 fix-8 — Dock window level + 1. Dock 자동 숨김 + 마우스 호버로 Dock 등장 시 popover 가 Dock 에 가려지지 않도록 *Dock 위 level* 강제.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.transient, .fullScreenAuxiliary, .canJoinAllSpaces]
        // TASK-058 fix-2 — *외부 앱 활성 상태에서 popover 첫 클릭 즉시 액션* 정합. `nonactivatingPanel` 은 *앱 자체 activate 차단* 만 보장 / *panel key window 활성화 단계*는 별도 → 기본 동작에서 첫 클릭이 panel key 활성화에 흡수 + 두 번째 클릭부터 view 액션. `becomesKeyOnlyIfNeeded = true` 박으면 *first responder 필요 view (NSTextField 검색바)* 클릭 시만 panel key 활성화 + 그 외 view (버튼 / 클립 행 / 자물쇠 / 일시정지 / 핀 사이드바 등) 는 key 활성화 우회 → 첫 클릭 즉시 view 액션. `FirstMouseHostingView.acceptsFirstMouse(for:)` true 와 조합 — *not-key window view mouseDown 받음 보장* + *panel key 활성화 단계 자체 우회* 두 정책 동시 필요.
        p.becomesKeyOnlyIfNeeded = true
        // TASK-060 — not-key panel 상태에서도 mouse moved 이벤트 dispatch 받아 SwiftUI .onHover NSTrackingArea 갱신 정상화. `becomesKeyOnlyIfNeeded = true` + `nonactivatingPanel` 조합으로 panel 이 대부분 not-key 상태 → NSPanel default `acceptsMouseMovedEvents = false` 면 mouse moved 차단 → `.onHover` 의 `mouseEntered:`/`mouseExited:` 콜백 발화 누락 → 클립 행 선택 하이라이트 (`selectedIdx`) 가 *이전 hover 위치 stuck* (마우스 시각 위치와 selection 위치 어긋남). 명시적 true 박아 hover 동기화 보장.
        p.acceptsMouseMovedEvents = true

        // 시스템 NSWindow 자체가 외곽 corner + 보더 + 그림자 박음 — VE 자체 cornerRadius/border 박지 X.
        // TASK-070 알려진 결함: .titled + .fullSizeContentView 조합에서 NSPanel framework 가 titlebar 영역 reserved 박아 SwiftUI body 가 titlebar 영역 만큼 아래로 박힘 (상단 padding 늘어남 / 하단 padding 줄어듦). ve.frame 강제 박음 시도 효과 X. 후속 task 에서 fix 위임.
        let ve = NSVisualEffectView(frame: contentRect)
        ve.material = .popover
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.isEmphasized = true
        ve.autoresizingMask = [.width, .height]
        p.contentView = ve

        return (p, ve)
    }

    /// TASK-075 — bubble + arrow 시각 paradigm 패널 헬퍼. 상세 sub-window 전용.
    /// `make` 와 분리 사유: `make` 는 TASK-070 에서 `.titled` styleMask + 시스템 chrome (corner + border + shadow) 박는 패턴 채택. 메인 popover / 핀 사이드바는 직사각형이라 정합, 그러나 상세 sub-window 는 `NSVisualEffectView.maskImage` 로 panel 자체를 bubble + arrow 모양으로 잘라내는 paradigm (TASK-027) — panel.frame 직사각형 외곽에 시스템 chrome 직사각형 outline 이 박히면 꼭지(arrow) 가 outline 안쪽에 갇혀 시각 어색.
    /// 해결: styleMask `.borderless + .nonactivatingPanel + .fullSizeContentView` (`.titled` / `.resizable` 제거) + `isOpaque=false` + `backgroundColor=.clear` → 시스템 chrome 박지 않음. `hasShadow=true` 는 transparent panel + alpha mask 기반 → bubble + arrow shape 따라 그림자 자연 정합.
    /// 공통 정책 (level / hidesOnDeactivate / collectionBehavior / becomesKeyOnlyIfNeeded / acceptsMouseMovedEvents) 은 `make` 와 동등 — popover 동반 시각 컴패니언으로 동일 동작 정책 필요.
    static func makeBubble(width: CGFloat, height: CGFloat) -> (panel: KeyablePanel, visualEffectView: NSVisualEffectView) {
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        let p = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.transient, .fullScreenAuxiliary, .canJoinAllSpaces]
        p.becomesKeyOnlyIfNeeded = true
        p.acceptsMouseMovedEvents = true

        // VE 는 maskImage 단독 책임 (PopoverWindow.makeBubbleMaskImage) — cornerRadius / border 박지 않음. mask 영역 밖은 transparent (panel backgroundColor=.clear + isOpaque=false 와 정합) → bubble + arrow shape 가 시각 결과.
        let ve = NSVisualEffectView(frame: contentRect)
        ve.material = .popover
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.isEmphasized = true
        ve.autoresizingMask = [.width, .height]
        p.contentView = ve

        return (p, ve)
    }

    /// SwiftUI rootView를 NSVisualEffectView 안 subview로 박음 (autoresizing — NSHostingView intrinsic 영향 차단).
    /// TASK-037 fix-10 — fix-9 의 4-edge constraint + fittingSize 조합이 *경쟁 사이클* 만듦 (NSHostingView intrinsic → NSPanel 자동 contentSize fit ↔ 우리 setFrame). autoresizing 박으면 NSHostingView 가 visualEffectView frame 단순 fill — intrinsic 가 NSPanel.frame 영향 X. PopoverWindow.refreshFrame 의 fittingSize 측정 + setFrame 으로 SwiftUI body intrinsic 과 NSPanel.frame 정확 일치 보장 (fix-7 의 mismatch 해소).
    /// TASK-058 fix-1 — `FirstMouseHostingView` 서브클래스 사용 → popover 전체 영역 *acceptsFirstMouse* 활성. 외부 앱 활성 상태에서 popover 의 클립 행 / 검색바 / 자물쇠 / 일시정지 / 핀 사이드바 등 *모든 view 클릭* 시 첫 클릭에 즉시 액션 처리 (panel key 활성 흡수 차단). 잠금 모드 ON 시 외부 앱 작업 후 popover 복귀 시나리오 정합.
    static func mount<Root: View>(_ rootView: Root, in visualEffectView: NSVisualEffectView) -> NSHostingView<AnyView> {
        // 기존 subview 제거
        visualEffectView.subviews.forEach { $0.removeFromSuperview() }

        let hosting = FirstMouseHostingView(rootView: AnyView(rootView))
        // TASK-071 Phase 3 — popover 상하단 여백 비대칭 fix (TASK-070 알려진 결함 후속).
        // root cause: PopoverPanel.make 의 `.titled + .fullSizeContentView` styleMask 조합 → NSWindow contentLayoutRect = frame - titlebar 영역 (≈28pt). NSHostingView 기본 동작이 contentLayoutRect 를 *top safe area* 로 SwiftUI body 에 전달 → SwiftUI body 가 titlebar height 만큼 아래로 shift → 상단 여백 늘어남 + 하단 컨텐츠 (설정 행) panel.frame 밖으로 밀려나 잘림.
        // fix: safeAreaRegions = [] 박음 (macOS 13.0+ 공식 API). SwiftUI body 가 frame 전체 사용 → titlebar safe area 추종 차단.
        // TASK-070 의 *ve.frame 강제 박음 효과 X* 시도는 NSVisualEffectView layer 영역 — 본 fix 는 NSHostingView ↔ SwiftUI 사이 인터페이스 layer (다른 영역).
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = visualEffectView.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        visualEffectView.addSubview(hosting)
        return hosting
    }

    /// 화면 anchor 5종 + inset 박아 panel 배치 (방식 2/3 공통, TASK-054).
    /// `PopoverAnchor` enum 5종 + visibleFrame 기준 origin 계산 (`PopoverAnchor.origin` 순수 함수 위임).
    /// 호출처는 환경설정 *기본 오픈 위치* (UserDefaults `popoverDefaultAnchor`) 조회 결과 전달. NSScreen.main 미존재 시 no-op.
    static func positionAtAnchor(_ panel: NSPanel, anchor: PopoverAnchor) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let inset: CGFloat = DesignTokens.WindowSize.popoverInsetBottom
        let origin = anchor.origin(panelSize: panel.frame.size, visibleFrame: visible, inset: inset)
        panel.setFrameOrigin(origin)
    }

    /// TASK-054 — 저장 좌표 유효성 검증 (순수 함수, 단위 테스트 진입점).
    /// TASK-054 fix-1 — width 도 영속이라 `validateSavedFrame` 으로 확장 (origin + size 통합 검증). 본 헬퍼는 호환 wrapper.
    /// - Returns: `validateSavedFrame(origin:size:visibleFrame:)` 결과 (panelSize 가 size 역할).
    static func validateSavedOrigin(origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> Bool {
        validateSavedFrame(origin: origin, size: panelSize, visibleFrame: visibleFrame)
    }

    /// TASK-054 fix-1 — 저장 frame (origin + size) 유효성 검증 (순수 함수, 단위 테스트 진입점).
    /// 유효 조건: size 가 visibleFrame 안 cap + origin 이 visibleFrame 안 + (origin + size) 가 visibleFrame 안.
    /// 모니터 분리 / 해상도 변경 / 저장된 width 가 cap 범위 밖 (사용자 설정 변경 후 cap 축소된 경우) 시 false.
    /// - Parameters:
    ///   - origin: UserDefaults 에 저장된 popover frame.origin (NSPanel bottom-up 좌표).
    ///   - size: 저장된 popover frame.size (width + height).
    ///   - visibleFrame: 현재 screen.visibleFrame.
    /// - Returns: 진입 가능 시 true / 화면 밖 또는 size 초과 시 false.
    static func validateSavedFrame(origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> Bool {
        // size 가 visibleFrame 초과 (모니터 너무 작음) → fallback.
        guard size.width <= visibleFrame.width, size.height <= visibleFrame.height else {
            return false
        }
        // origin + size 가 visibleFrame 안 + panel 우/상단도 visibleFrame 안.
        return origin.x >= visibleFrame.minX
            && origin.y >= visibleFrame.minY
            && origin.x + size.width <= visibleFrame.maxX
            && origin.y + size.height <= visibleFrame.maxY
    }

    /// 메뉴바 button 아래 정렬 + 좌우 화면 클램프 (방식 1)
    /// - Returns: anchorOffsetX (panel 좌표계 안 button center x — arrow tail 위치)
    @discardableResult
    static func positionBelow(panel: NSPanel, button: NSStatusBarButton) -> CGFloat {
        guard let buttonWindow = button.window else { return panel.frame.width / 2 }
        let buttonRectInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let idealX = buttonRectInScreen.midX - panelSize.width / 2
        let clampedX = max(visible.minX + 8, min(idealX, visible.maxX - panelSize.width - 8))
        let originY = buttonRectInScreen.minY - panelSize.height - 4

        panel.setFrameOrigin(NSPoint(x: clampedX, y: originY))
        return buttonRectInScreen.midX - clampedX
    }

    /// 클립 paste 흐름 (TASK-016 D-4·D-5·D-6) — popover dismiss → 이전 frontmost 앱 활성화 → 안정 대기 → viewModel.paste.
    /// Method1/2/3Window 모두 동일 흐름 — DRY로 묶음.
    /// TASK-028 — `zone` 호출 시점 snapshot 을 viewModel.paste 에 명시 전달. hide() → collapsePinSidebar() → focusZone=.clip 흐름이 paste 대상에 영향 X.
    /// TASK-058 — `viewModel.keepOpenAfterAction` true 시 `hide()` + `sleep` skip → 바로 paste 합성 (FEATURES F-011). `nonactivatingPanel` + `NSApp.activate` 미호출 정책 정합 — popover 가 떠 있어도 외부 앱 frontmost 보존.
    static func performPasteFlow(
        viewModel: ClipsViewModel,
        idx: Int,
        zone: FocusZone,
        sourceLabel: String,
        hide: () -> Void
    ) async {
        // TASK-020 — NSApp.activate / prev.activate 호출 모두 제거. 외부 앱이 frontmost 유지 상태라 별도 activate 단계 없이 panel hide + sleep + viewModel.paste만으로 정확 paste 보장.
        // TASK-058 — 유지 모드 ON 시 hide() + sleep skip → 바로 paste 합성.
        if !viewModel.keepOpenAfterAction {
            hide()
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.Animation.appActivationDelay * 1000)))
        }
        await viewModel.paste(at: idx, zone: zone)
    }

    /// 클립 copy 흐름 (TASK-024) — popover dismiss → 안정 대기 → viewModel.copy. `performPasteFlow` 와 동일 패턴 (mode 만 `.copyBack` 강제). Settings `pasteMode` 라디오 무관 항상 클립보드 갱신만, ⌘V 합성 X. Accessibility 권한 무관.
    /// TASK-028 — `zone` 호출 시점 snapshot 을 viewModel.copy 에 명시 전달. performPasteFlow 와 동일 사유.
    /// TASK-058 — `viewModel.keepOpenAfterAction` true 시 `hide()` + `sleep` skip → 바로 클립보드 갱신.
    static func performCopyFlow(
        viewModel: ClipsViewModel,
        idx: Int,
        zone: FocusZone,
        sourceLabel: String,
        hide: () -> Void
    ) async {
        if !viewModel.keepOpenAfterAction {
            hide()
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.Animation.appActivationDelay * 1000)))
        }
        await viewModel.copy(at: idx, zone: zone)
    }

    /// KeyablePanel.keyDownHandler 셋업 — Method1/2/3 공통 키 이벤트 처리 (TASK-017).
    /// SwiftUI .onKeyPress가 NSPanel(.nonactivatingPanel) 환경에서 발화 안 해 AppKit 단에서 직접 처리.
    /// 단축키 정의는 PopoverHotkey enum (단일 진실 소스) — 본 함수는 매칭 후 dispatch만.
    static func installKeyDownHandler(
        panel: KeyablePanel,
        viewModel: ClipsViewModel,
        mode: PopoverInvocationMode,
        onDismiss: @escaping @MainActor () -> Void,
        handleClipPaste: @escaping @MainActor (Int, FocusZone) async -> Void,
        handleClipCopy: @escaping @MainActor (Int, FocusZone) async -> Void
    ) {
        panel.keyDownHandler = { [weak viewModel, weak panel] event in
            guard let viewModel, let panel else { return false }
            for hotkey in PopoverHotkey.allCases where hotkey.matches(event: event) {
                return Self.dispatch(
                    hotkey: hotkey,
                    viewModel: viewModel,
                    panel: panel,
                    mode: mode,
                    onDismiss: onDismiss,
                    handleClipPaste: handleClipPaste,
                    handleClipCopy: handleClipCopy
                )
            }
            return false  // 매칭 단축키 없음 → super 호출 (NSTextField로 forward)
        }
    }

    /// PopoverHotkey 별 액션 dispatch — installKeyDownHandler 매칭 후 호출.
    /// 반환 true = 처리 완료 (super 호출 차단) / false = 미처리 (NSTextField 등으로 forward).
    private static func dispatch(
        hotkey: PopoverHotkey,
        viewModel: ClipsViewModel,
        panel: KeyablePanel,
        mode: PopoverInvocationMode,
        onDismiss: @escaping @MainActor () -> Void,
        handleClipPaste: @escaping @MainActor (Int, FocusZone) async -> Void,
        handleClipCopy: @escaping @MainActor (Int, FocusZone) async -> Void
    ) -> Bool {
        switch hotkey {
        case .moveSelectionUp:
            viewModel.moveSelectionUp()
            return true
        case .moveSelectionDown:
            viewModel.moveSelectionDown()
            return true
        case .pageUp:
            // TASK-036 — ⌘+↑ 페이지 위 (가시 행 수만큼). focusZone 분기 + clamp 는 ClipsViewModel 내부.
            viewModel.pageUp()
            return true
        case .pageDown:
            // TASK-036 — ⌘+↓ 페이지 아래 (가시 행 수만큼).
            viewModel.pageDown()
            return true
        case .moveSelectionToFirst:
            // TASK-036 — ⌘+⇧+↑ 맨 위 (Home). focusZone 분기는 ClipsViewModel 내부.
            viewModel.moveSelectionToFirst()
            return true
        case .moveSelectionToLast:
            // TASK-036 — ⌘+⇧+↓ 맨 아래 (End).
            viewModel.moveSelectionToLast()
            return true
        case .togglePin:
            // TASK-019 — focusZone == .pin 이면 *pinnedClips 안 항목 unpin*. .clip 이면 본체 toggle.
            if viewModel.focusZone == .pin {
                let pinIdx = viewModel.pinSelectedIdx
                if pinIdx >= 0 && pinIdx < viewModel.pinnedClips.count {
                    let targetId = viewModel.pinnedClips[pinIdx].id
                    Task { await viewModel.togglePin(id: targetId, trackSelection: .pin) }
                }
            } else {
                Task { await viewModel.togglePin(at: viewModel.selectedIdx) }
            }
            return true
        case .togglePinSidebar:
            // TASK-019 — ⌘+B 단일 토글 단축키. 빈 핀 상태에서 togglePinSidebar() 내부 가드로 no-op. 방식 3 (보류) 차단.
            guard mode != .method3 else { return false }
            viewModel.togglePinSidebar()
            return true
        case .deleteOne:
            Task { await viewModel.delete(at: viewModel.activeIdx) }
            return true
        case .deleteAll:
            Task { await viewModel.deleteAllExceptPinned() }
            return true
        case .copy:
            // TASK-024 — ⌘+C 권한 무관 항상 활성. Settings `pasteMode` 라디오 무관 항상 `.copyBack` 호출.
            // TASK-028 — dispatch 진입 시점 zone + activeIdx snapshot. hide() 흐름이 focusZone 리셋해도 copy 대상 변동 X.
            do {
                let zone = viewModel.focusZone
                let idx = viewModel.activeIdx
                Task { @MainActor in await handleClipCopy(idx, zone) }
            }
            return true
        case .paste:
            // TASK-024 — Accessibility 권한 게이트. 권한 X 시 event consume + 무반응 (NSTextField forward 차단).
            guard viewModel.accessibilityGranted else {
                Logger.ui.debug("⌘V blocked — accessibility denied (TASK-024 게이트)")
                return true
            }
            // TASK-028 — dispatch 진입 시점 zone + activeIdx snapshot. copy 와 동일 사유.
            do {
                let zone = viewModel.focusZone
                let idx = viewModel.activeIdx
                Task { @MainActor in await handleClipPaste(idx, zone) }
            }
            return true
        case .confirm:
            // TASK-051 — Enter 키 (일반 36 + Numpad 76) autoPasteEnabled 분기 라우팅.
            // autoPasteEnabled = true → handleClipPaste (⌘V 와 동일 흐름) / false → handleClipCopy (⌘C 와 동일 흐름).
            // 권한 X 정합: SettingsViewModel.updateAccessibilityGranted O→X 회수 시 autoPasteEnabled 강제 OFF — 자연스러운 copy 폴백.
            // 안전망: handleClipPaste 경로의 ClipsViewModel.paste 가 effectiveMode 매트릭스로 권한 X 시 .copyBack 자동 폴백.
            // IME marked text 보호 가드는 installPopoverKeyEventMonitor 가 매칭 루프 직전 처리.
            do {
                let zone = viewModel.focusZone
                let idx = viewModel.activeIdx
                let auto = UserDefaults.standard.bool(forKey: "autoPasteEnabled")
                Logger.ui.debug("Enter dispatched — autoPasteEnabled=\(auto, privacy: .public) zone=\(zone.rawValue, privacy: .public) idx=\(idx, privacy: .public)")
                Task { @MainActor in
                    if auto {
                        await handleClipPaste(idx, zone)
                    } else {
                        await handleClipCopy(idx, zone)
                    }
                }
            }
            return true
        case .escape:
            // TASK-025 — 2-tier 단순화. 검색어 clear 분기 폐기 (검색 활성 단계 개념 제거).
            // 핀 사이드바 열림 → 사이드바만 닫기 / 그 외 → popover dismiss.
            if viewModel.pinSidebarOpen {
                viewModel.collapsePinSidebar()
                return true
            }
            // TASK-058 fix-5/6 — ESC 는 잠금 ON 이어도 close 예외 진입점 (macOS 표준 dismiss 키). 외부 클릭 / 트레이 재클릭 / ⌘⇧V 재호출 차단은 유지. fix-6 정정 — 자물쇠 상태는 *유지* (앱 세션 영속) — onDismiss closure 가 `hide(force: true)` 호출로 가드 우회. ESC close 후 다음 popover 진입 시 마지막 자물쇠 상태 복원.
            Task { @MainActor in onDismiss() }
            return true
        case .toggleClipDetail:
            // TASK-055 — 활성 클립 상세 sub-window toggle. clipDetailVisible 분기로 close / 활성 행 Provider 매칭 검증 후 emit.
            // 방식 3 (보류) 차단 — detail sub-window 자체가 method3 에서 진입 X (PopoverWindow.showClipDetailPanel 가드).
            guard mode != .method3 else { return false }
            viewModel.triggerClipDetail()
            return true
        }
    }

    /// TASK-025 — popover 키 라우팅 monitor. NSTextField 가 first responder 일 때 NSTextView (field editor) 가 keyDown 을 *먼저* consume 하므로 `KeyablePanel.keyDownHandler` 미발화.
    /// 본 monitor 가 NSEvent dispatch chain 의 NSResponder chain *전 단계* 에서 발화 — NSTextView consume 전 가로채 PopoverHotkey 매칭 시 dispatch.
    /// Tab 키 (keyCode=48) 도 consume — NSTextView `insertTab:` 가 first responder 변경 가능성 차단 (always-active 안전망).
    /// 매칭 안 되는 키 (printable / Space / Backspace / ←→ / IME / NSTextView 표준 단축키) 는 `return event` forward.
    /// 반환된 monitor 객체는 호출자가 보관하다 NSEvent.removeMonitor 로 정리.
    static func installPopoverKeyEventMonitor(
        panel: KeyablePanel,
        viewModel: ClipsViewModel,
        mode: PopoverInvocationMode,
        onDismiss: @escaping @MainActor () -> Void,
        handleClipPaste: @escaping @MainActor (Int, FocusZone) async -> Void,
        handleClipCopy: @escaping @MainActor (Int, FocusZone) async -> Void
    ) -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak panel, weak viewModel] event in
            guard let panel, let viewModel, event.window === panel else { return event }
            // TASK-051 — IME marked text 가드. 검색바 NSTextField first responder 의 field editor (NSTextView) 에
            // marked text (한글/일본어/중국어 IME 변환 중간 상태) 가 있을 때 Enter 누르면 *변환 확정* 의도이므로
            // confirm dispatch 차단 + NSTextView forward. monitor 가 NSResponder chain 전 단계에서 발화하므로
            // NSTextInputContext.handleEvent (IME 처리) 전에 가드 박아야 정확.
            if event.keyCode == 36 || event.keyCode == 76 {
                if let textField = PopoverPanel.findFirstTextField(in: panel.contentView),
                   let editor = textField.currentEditor() as? NSTextView,
                   editor.hasMarkedText() {
                    Logger.ui.debug("Enter forwarded — IME marked text detected (TASK-051)")
                    return event
                }
            }
            // PopoverHotkey 매칭 가로채 dispatch.
            for hotkey in PopoverHotkey.allCases where hotkey.matches(event: event) {
                let handled = Self.dispatch(
                    hotkey: hotkey,
                    viewModel: viewModel,
                    panel: panel,
                    mode: mode,
                    onDismiss: onDismiss,
                    handleClipPaste: handleClipPaste,
                    handleClipCopy: handleClipCopy
                )
                return handled ? nil : event
            }
            // Tab 키 안전망 — NSTextView `insertTab:` 매핑 차단 (first responder 잃지 않도록).
            if event.keyCode == 48 {  // Tab
                Logger.ui.debug("Tab consumed by popover key monitor (TASK-025)")
                return nil
            }
            return event  // 미매칭 — NSTextField forward (printable / Space / Backspace / ←→ / IME / Cmd+A 등).
        }
    }

    /// 트리 탐색 — view subview 재귀로 첫 NSTextField 찾기.
    /// TASK-025 — popover open 시 NSTextField first responder 자동 진입에 사용 (`PopoverWindow.showInternal`).
    /// internal 가시성 — 같은 모듈 내 `PopoverWindow` 가 호출.
    static func findFirstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField { return tf }
        for sub in view.subviews {
            if let tf = findFirstTextField(in: sub) {
                return tf
            }
        }
        return nil
    }

    /// TASK-025 — popover 안 mouseDown 시 NSTextField 외부 click 이면 NSTextField *first responder 복원* (always-active 정책).
    /// 클립 행 / 핀 행 / 환경설정 행 click 처리 후에도 검색바가 keystroke 받도록 보장.
    /// 이전 정책 (TASK-016 D-3) — *해제* 방향 → TASK-025 — *복원* 방향으로 반대 갱신.
    /// 반환된 monitor 객체는 호출자가 보관하다 NSEvent.removeMonitor 로 정리.
    static func installSearchFirstResponderRestoreMonitor(panel: NSPanel) -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak panel] event in
            guard let panel, event.window === panel else { return event }
            guard let contentView = panel.contentView else { return event }
            let hitView = contentView.hitTest(event.locationInWindow)
            var isTextFieldHit = false
            var current: NSView? = hitView
            while let v = current {
                if v is NSTextField || v is NSTextView {
                    isTextFieldHit = true
                    break
                }
                current = v.superview
            }
            // NSTextField 외부 click → first responder 가 NSTextField 아니면 복원.
            if !isTextFieldHit,
               let textField = findFirstTextField(in: contentView),
               panel.firstResponder !== textField,
               panel.firstResponder !== textField.currentEditor() {
                panel.makeFirstResponder(textField)
                Logger.ui.debug("Search first responder restored after outside click (TASK-025)")
            }
            return event
        }
    }
}

/// 외부 마우스 클릭으로 popover 닫기 (방식 1/3 공통)
@MainActor
final class OutsideClickMonitor {
    private var monitor: Any?
    private let onClick: @MainActor () -> Void

    init(onClick: @MainActor @escaping () -> Void) {
        self.onClick = onClick
    }

    func install() {
        remove()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onClick()
            }
        }
    }

    func remove() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // deinit 시점 cleanup은 nonisolated context 한계로 생략 — 호출자가 명시적으로 remove() 호출
}

/// TASK-058 fix-1 — popover NSHostingView 서브클래스. `acceptsFirstMouse(for:)` true 반환으로 popover 전체 영역 *첫 클릭 즉시 액션 처리* 활성.
/// 배경: NSPanel `nonactivatingPanel` 패턴은 *앱 자체 activate X* 보장하지만, *panel 자체는 key window* 가 되어야 view 이벤트 받음.
/// 외부 앱 활성 상태에서 popover view 클릭 시 기본 동작 = 첫 클릭이 panel key 활성 흡수 / 두 번째 클릭이 실제 view 액션.
/// `acceptsFirstMouse(for:)` true 박으면 첫 클릭에 panel key 활성 + view 이벤트 *동시* 처리 — 사용자가 두 번 클릭할 필요 X.
/// 잠금 모드 (F-011) ON 시 popover 가 외부 앱 작업 중에도 유지되므로 외부 앱 활성 후 popover 복귀 시나리오 정합 필수.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
