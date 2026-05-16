// Method1/2/3 공통 NSPanel + NSVisualEffectView setup 헬퍼 (UI Layer 중복 제거)
import AppKit
import SwiftUI
import OSLog

/// popover 안 단축키 정의 — 키코드 + modifier 조합의 단일 진실 소스 (TASK-017 / TASK-021).
/// FEATURES §4 정합 + 사용자 결정: 행 조작 단축키 중 방향키(↑/↓)·Enter·ESC만 단독, 나머지는 ⌘ 부여.
/// PopoverPanel.installKeyDownHandler가 본 enum을 순회 매칭 → dispatch 분기.
enum PopoverHotkey: CaseIterable {
    case moveSelectionUp        // ↑ 단독 (TASK-021)
    case moveSelectionDown      // ↓ 단독 (TASK-021)
    case togglePin              // ⌘+P
    case togglePinSidebar       // ⌘+B (TASK-019 — 이전 ⌘+→/⌘+← 분리 단축키 → 단일 토글 단축키로 통합. FEATURES §3-7 / §4 9항)
    case deleteOne              // ⌘+⌫
    case deleteAll              // ⌥+⌘+⌫
    case deleteAllAlias         // ⌘+⇧+⌫
    case paste                  // ⌘+V
    case activateSearch         // Enter 단독 (예외 — macOS 표준 검색 활성화)
    case escape                 // ESC 단독 (예외 — macOS 표준 닫기/취소)

    /// macOS keyCode (NSEvent.keyCode raw 값).
    var keyCode: UInt16 {
        switch self {
        case .moveSelectionUp: return 126        // ↑
        case .moveSelectionDown: return 125      // ↓
        case .togglePin: return 35               // P
        case .togglePinSidebar: return 11        // B
        case .deleteOne, .deleteAll, .deleteAllAlias: return 51  // Backspace (.delete)
        case .paste: return 9                    // V
        case .activateSearch: return 36          // Enter (return)
        case .escape: return 53                  // ESC
        }
    }

    /// meaningful modifier 조합 (.command/.shift/.option/.control 4개만). .numericPad/.function 제외.
    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .togglePin, .togglePinSidebar,
             .deleteOne, .paste:
            return [.command]
        case .deleteAllAlias:
            return [.command, .shift]
        case .deleteAll:
            return [.command, .option]
        case .moveSelectionUp, .moveSelectionDown,
             .activateSearch, .escape:
            return []
        }
    }

    /// event 매칭 — keyCode + meaningful modifiers 일치 시 true.
    /// .numericPad/.function modifier는 무시 (방향키가 자동으로 박음 — 매칭 false 회피).
    func matches(event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let meaningful: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return event.modifierFlags.intersection(meaningful) == modifiers
    }
}

@MainActor
enum PopoverPanel {
    /// borderless KeyablePanel + contentView=NSVisualEffectView (Liquid Glass 표준 패턴)
    static func make(width: CGFloat, height: CGFloat) -> (panel: KeyablePanel, visualEffectView: NSVisualEffectView) {
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        let p = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.transient, .fullScreenAuxiliary, .canJoinAllSpaces]

        let ve = NSVisualEffectView(frame: contentRect)
        ve.material = .popover
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.isEmphasized = true
        ve.wantsLayer = true
        ve.layer?.cornerRadius = DesignTokens.Radius.popoverOuter
        ve.layer?.masksToBounds = true
        ve.layer?.borderWidth = 0.5
        ve.layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        ve.autoresizingMask = [.width, .height]
        p.contentView = ve

        return (p, ve)
    }

    /// SwiftUI rootView를 NSVisualEffectView 안 subview로 박음 (transparent layer + 4-edge constraint)
    static func mount<Root: View>(_ rootView: Root, in visualEffectView: NSVisualEffectView) -> NSHostingView<AnyView> {
        // 기존 subview 제거
        visualEffectView.subviews.forEach { $0.removeFromSuperview() }

        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        visualEffectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])
        return hosting
    }

    /// 화면 우하단에 panel 배치 (방식 2/3 공통)
    static func positionAtBottomRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let w: CGFloat = DesignTokens.WindowSize.popoverWidth
        let inset: CGFloat = DesignTokens.WindowSize.popoverInsetBottom
        let origin = NSPoint(
            x: visible.maxX - w - inset,
            y: visible.minY + inset
        )
        panel.setFrameOrigin(origin)
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
    static func performPasteFlow(
        viewModel: ClipsViewModel,
        idx: Int,
        sourceLabel: String,
        hide: () -> Void
    ) async {
        // TASK-020 — NSApp.activate / prev.activate 호출 모두 제거. 외부 앱이 frontmost 유지 상태라 별도 activate 단계 없이 panel hide + sleep + viewModel.paste만으로 정확 paste 보장.
        hide()
        try? await Task.sleep(for: .milliseconds(Int(DesignTokens.Animation.appActivationDelay * 1000)))
        await viewModel.paste(at: idx)
    }

    /// KeyablePanel.keyDownHandler 셋업 — Method1/2/3 공통 키 이벤트 처리 (TASK-017).
    /// SwiftUI .onKeyPress가 NSPanel(.nonactivatingPanel) 환경에서 발화 안 해 AppKit 단에서 직접 처리.
    /// 단축키 정의는 PopoverHotkey enum (단일 진실 소스) — 본 함수는 매칭 후 dispatch만.
    static func installKeyDownHandler(
        panel: KeyablePanel,
        viewModel: ClipsViewModel,
        mode: PopoverInvocationMode,
        onDismiss: @escaping @MainActor () -> Void,
        handleClipPaste: @escaping @MainActor (Int) async -> Void
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
                    handleClipPaste: handleClipPaste
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
        handleClipPaste: @escaping @MainActor (Int) async -> Void
    ) -> Bool {
        switch hotkey {
        case .moveSelectionUp:
            viewModel.moveSelectionUp()
            return true
        case .moveSelectionDown:
            viewModel.moveSelectionDown()
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
        case .deleteAll, .deleteAllAlias:
            Task { await viewModel.deleteAllExceptPinned() }
            return true
        case .paste:
            Task { @MainActor in await handleClipPaste(viewModel.activeIdx) }
            return true
        case .activateSearch:
            // Enter 단독 — focusZone=.search & 비활성 시만 활성화. 그 외는 NSTextField로 흐름.
            guard viewModel.focusZone == .search, !viewModel.searchInputActive else { return false }
            viewModel.activateSearchInput()
            // 마우스 click과 동일하게 텍스트 커서 활성화 — NSTextField 명시적 first responder 셋업.
            if let textField = Self.findFirstTextField(in: panel.contentView) {
                panel.makeFirstResponder(textField)
            }
            return true
        case .escape:
            // ESC 단독 — 검색 활성 시는 installSearchEscapeMonitor가 NSTextView consume 전에 가로챔.
            // 본 분기는 검색 비활성 상태 ESC만 도달 — 안전장치로 동일 처리 유지 (monitor 미설치 fallback).
            if viewModel.searchInputActive {
                viewModel.deactivateSearchInputAndClear()
                panel.makeFirstResponder(nil)
                return true
            }
            if viewModel.pinSidebarOpen {
                viewModel.collapsePinSidebar()
                return true
            }
            Task { @MainActor in onDismiss() }
            return true
        }
    }

    /// ESC 키 monitor — 검색 활성 상태에서 ESC 누름 시 NSTextView field editor가 consume하기 *전에* 가로채 검색 비활성화 + first responder 해제.
    /// addLocalMonitorForEvents([.keyDown])는 NSTextView dispatch 전에 호출 — 마우스 외부 클릭 monitor와 동일 패턴 (TASK-017 fix-3 v4).
    /// 반환된 monitor 객체는 호출자가 보관하다 NSEvent.removeMonitor로 정리.
    static func installSearchEscapeMonitor(panel: KeyablePanel, viewModel: ClipsViewModel) -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak panel, weak viewModel] event in
            guard let panel, let viewModel, event.window === panel else { return event }
            // ESC keyCode 53 + 검색 활성 상태일 때만 가로챔. 그 외는 forward.
            guard event.keyCode == 53, viewModel.searchInputActive else { return event }
            viewModel.deactivateSearchInputAndClear()
            panel.makeFirstResponder(nil)
            return nil  // event consume → NSTextView로 forward 안 됨
        }
    }

    /// 트리 탐색 — view subview 재귀로 첫 NSTextField 찾기. Enter 단축키 시 검색부 텍스트 커서 활성화용 (TASK-017 fix-3).
    private static func findFirstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField { return tf }
        for sub in view.subviews {
            if let tf = findFirstTextField(in: sub) {
                return tf
            }
        }
        return nil
    }

    /// popover 안 mouseDown 시 검색바 외부 click이면 first responder reset (TASK-016 D-3 outside click deactivate).
    /// click 좌표가 NSTextField/NSTextView hit이면 reset 안 함 → SwiftUI HostingView가 click 처리해 NSTextField가 first responder 다시 받음.
    /// 반환된 monitor 객체는 호출자가 보관하다 NSEvent.removeMonitor로 정리.
    static func installOutsideTextFieldClickMonitor(panel: NSPanel) -> Any? {
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
            // 외부 click(검색바 외부) 시 first responder reset (TASK-016 D-3 outside click deactivate).
            if !isTextFieldHit, let firstResp = panel.firstResponder, firstResp !== panel {
                panel.makeFirstResponder(panel)
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
