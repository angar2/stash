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

    // TASK-066 — ttl param optional (nil = kind.defaultTTL 자동 추종)
    func enqueue(_ kind: ToastKind, _ text: String, ttl: TimeInterval? = nil) {
        let effectiveTTL = ttl ?? kind.defaultTTL
        let item = ToastItem(kind: kind, text: text, ttl: effectiveTTL)
        stack.append(item)
        Logger.ui.info("Toast enqueue — kind=\(String(describing: kind), privacy: .public) ttl=\(effectiveTTL, privacy: .public) text=\(text, privacy: .public)")
        ensurePanelVisible()
        dismissTasks[item.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(effectiveTTL * 1_000_000_000))
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
        } else {
            updatePanelFrame()
        }
    }

    func attachPanel(_ panel: NSPanel) {
        self.panel = panel
    }

    private func ensurePanelVisible() {
        guard let panel else { return }
        updatePanelFrame()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // TASK-066 — panel frame 을 NSHostingView.fittingSize 에 추종. height 300pt 고정 폐기.
    // SwiftUI body 재계산 비동기성 — DispatchQueue.main.async 로 layout 완료 후 fittingSize 계산.
    private func updatePanelFrame() {
        guard let panel, let hosting = panel.contentView else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let screen = NSScreen.main else { return }
            let fittingSize = hosting.fittingSize
            let width = DesignTokens.WindowSize.toastMaxWidth
            let height = max(fittingSize.height, 1)
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - width - DesignTokens.WindowSize.toastInsetRight,
                y: visible.maxY - height - DesignTokens.WindowSize.toastInsetTop
            )
            Logger.ui.debug("Toast panel frame — fitting=\(fittingSize.debugDescription, privacy: .public) height=\(height, privacy: .public) stackCount=\(self.stack.count, privacy: .public)")
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        }
    }
}

@MainActor
final class ToastWindowController {
    private let panel: NSPanel
    private let queue: ToastQueue

    init(queue: ToastQueue) {
        self.queue = queue
        // TASK-066 — height 는 첫 enqueue 후 fittingSize 추종으로 갱신됨. 초기값은 placeholder.
        let contentRect = NSRect(x: 0, y: 0, width: DesignTokens.WindowSize.toastMaxWidth, height: 100)
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
        // TASK-066 — Spacer + maxHeight 제거. panel frame 이 fittingSize 추종이라 stack 누적 높이만큼만 panel 영역.
        VStack(alignment: .trailing, spacing: DesignTokens.Spacing.sm) {
            ForEach(queue.stack) { item in
                ToastView(item: item, onDismiss: { queue.dismiss(id: item.id) })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .animation(.easeInOut(duration: 0.2), value: queue.stack.count)
    }
}
