// ToastQueue + floating NSPanel (top 38 / right 20) — popover 인라인 토스트 발행 + TTL 자동 dismiss (UX-UI §6 정합)
import AppKit
import SwiftUI
import Observation
import OSLog

@MainActor
@Observable
final class ToastQueue {
    var stack: [ToastItem] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private weak var panel: NSPanel?

    func enqueue(_ kind: ToastKind, _ text: String, ttl: TimeInterval = DesignTokens.Animation.toastTTLDefault) {
        let item = ToastItem(kind: kind, text: text, ttl: ttl)
        stack.append(item)
        Logger.ui.info("Toast enqueue — \(text, privacy: .public)")
        ensurePanelVisible()
        dismissTasks[item.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
            if !Task.isCancelled {
                self?.dismiss(id: item.id)
            }
        }
    }

    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
        stack.removeAll { $0.id == id }
        if stack.isEmpty {
            panel?.orderOut(nil)
        }
    }

    func attachPanel(_ panel: NSPanel) {
        self.panel = panel
    }

    private func ensurePanelVisible() {
        guard let panel else { return }
        if !panel.isVisible {
            positionPanel(panel)
            panel.orderFrontRegardless()
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width: CGFloat = DesignTokens.WindowSize.toastMaxWidth
        let height: CGFloat = 300
        let origin = NSPoint(
            x: visible.maxX - width - DesignTokens.WindowSize.toastInsetRight,
            y: visible.maxY - height - DesignTokens.WindowSize.toastInsetTop
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }
}

@MainActor
final class ToastWindowController {
    private let panel: NSPanel
    private let queue: ToastQueue

    init(queue: ToastQueue) {
        self.queue = queue
        let contentRect = NSRect(x: 0, y: 0, width: DesignTokens.WindowSize.toastMaxWidth, height: 300)
        let p = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.ignoresMouseEvents = false
        self.panel = p
        queue.attachPanel(p)
        let hosting = NSHostingView(rootView: ToastContainer(queue: queue))
        p.contentView = hosting
    }
}

private struct ToastContainer: View {
    @Bindable var queue: ToastQueue

    var body: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.Spacing.sm) {
            ForEach(queue.stack) { item in
                ToastView(item: item, onDismiss: { queue.dismiss(id: item.id) })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.easeInOut(duration: 0.2), value: queue.stack.count)
    }
}
