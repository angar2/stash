// ⌘ hold (200ms) + ⌘ double-tap (250ms 이내 두 번) 글로벌 modifier 감지 Service (ARCHITECTURE §2 / TASK-015 정합)
// NSEvent.addGlobalMonitorForEvents / .addLocalMonitorForEvents (flagsChanged) 사용. Accessibility 권한 필요.
import AppKit
import OSLog

@MainActor
final class HotkeyMonitor {
    var onHoldStart: (@MainActor () -> Void)?
    var onHoldEnd:   (@MainActor () -> Void)?
    var onDoubleTap: (@MainActor () -> Void)?

    private let permissionService: PermissionService
    private let holdThreshold: TimeInterval
    private let doubleTapInterval: TimeInterval

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var commandDownAt: Date?
    private var lastCommandUpAt: Date?
    private var holdWorkItem: DispatchWorkItem?
    private var holdActive: Bool = false

    init(
        permissionService: PermissionService,
        holdThreshold: TimeInterval = Constants.hotkeyHoldThresholdSeconds,
        doubleTapInterval: TimeInterval = Constants.hotkeyDoubleTapIntervalSeconds
    ) {
        self.permissionService = permissionService
        self.holdThreshold = holdThreshold
        self.doubleTapInterval = doubleTapInterval
    }

    func start() async {
        let status = await permissionService.currentStatus()
        guard status == .granted else {
            Logger.hotkey.warning("HotkeyMonitor start skipped — Accessibility 권한 없음 (\(String(describing: status)))")
            return
        }
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
            return event
        }
        Logger.hotkey.info("HotkeyMonitor started — global + local flagsChanged monitor 등록")
    }

    func stop() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
        holdWorkItem?.cancel()
        holdWorkItem = nil
        commandDownAt = nil
        if holdActive {
            holdActive = false
            onHoldEnd?()
        }
        Logger.hotkey.info("HotkeyMonitor stopped")
    }

    private func handle(event: NSEvent) {
        let isCommandDown = event.modifierFlags.contains(.command)
        // 다른 modifier (shift/option/control) 함께 눌렸으면 ⌘ 단독 트리거 X — 사용자 다른 단축키 조합 중
        let onlyCommand = isCommandDown && !event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.control)

        if onlyCommand && commandDownAt == nil {
            commandDownEvent()
        } else if !isCommandDown && commandDownAt != nil {
            commandUpEvent()
        }
    }

    private func commandDownEvent() {
        commandDownAt = Date()
        let lastUp = lastCommandUpAt
        if let lastUp, Date().timeIntervalSince(lastUp) < doubleTapInterval {
            lastCommandUpAt = nil
            Logger.hotkey.info("HotkeyMonitor trigger — ⌘ double-tap")
            onDoubleTap?()
        }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.commandDownAt != nil else { return }
                self.holdActive = true
                Logger.hotkey.info("HotkeyMonitor trigger — ⌘ hold start")
                self.onHoldStart?()
            }
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: item)
    }

    private func commandUpEvent() {
        let downAt = commandDownAt
        commandDownAt = nil
        holdWorkItem?.cancel()
        holdWorkItem = nil
        if holdActive {
            holdActive = false
            Logger.hotkey.info("HotkeyMonitor trigger — ⌘ hold end")
            onHoldEnd?()
            lastCommandUpAt = nil  // hold 이후 즉시 double-tap 조합 방지
        } else if downAt != nil {
            lastCommandUpAt = Date()
        }
    }
}
