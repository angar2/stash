// Method1/2/3 공통 NSPanel + NSVisualEffectView setup 헬퍼 (UI Layer 중복 제거)
import AppKit
import SwiftUI
import OSLog

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
        hide()
        if let prev = FrontmostAppTracker.shared.previousApp {
            prev.activate(options: [])
            Logger.ui.info("\(sourceLabel, privacy: .public): restored frontmost app \(prev.bundleIdentifier ?? "unknown", privacy: .public) before paste")
        } else {
            Logger.ui.warning("\(sourceLabel, privacy: .public): tracker.previousApp is nil — paste will go to current frontmost")
        }
        try? await Task.sleep(for: .milliseconds(Int(DesignTokens.Animation.appActivationDelay * 1000)))
        await viewModel.paste(at: idx)
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
