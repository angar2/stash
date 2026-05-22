// ⌘ hold (200ms) 글로벌 modifier 감지 Service (ARCHITECTURE §2 / TASK-015 정합)
// NSEvent.addGlobalMonitorForEvents / .addLocalMonitorForEvents (flagsChanged) 사용. Accessibility 권한 필요.
// ⌘ hold 분기는 TASK-018 Phase 9 *v1.0 보류* — 호출 사이트 (`onHoldStart` / `onHoldEnd`) 미연결. 코드 분기는 미래 부활 가능 유지.
// TASK-046 — ⌘ double-tap 진입 트리거 폐기 (잔존 버그 fix). 방식 2 popover 호출 자체는 유지 — 트리거가 ⌘ double-tap → ⌘⇧V SPM 으로 *변경* (TASK-032 시점 ⌘⇧V SPM 단축키가 *방식 2 단축키 변경* 의도였으나 plan 명명 *방식 4* 신규 진입점으로 잘못 분리 박힘 — 본 task로 명명 정합 *방식 4 폐기 + 방식 2 트리거 = ⌘⇧V SPM* 통합). ⌘ double-tap 영역 (onDoubleTap / doubleTapInterval / lastCommandUpAt) 코드 + Constants 잔존 일괄 제거.
import AppKit
import OSLog

@MainActor
final class HotkeyMonitor {
    var onHoldStart: (@MainActor () -> Void)?
    var onHoldEnd:   (@MainActor () -> Void)?

    private let permissionService: PermissionService
    private let holdThreshold: TimeInterval

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var commandDownAt: Date?
    private var holdWorkItem: DispatchWorkItem?
    private var holdActive: Bool = false

    init(
        permissionService: PermissionService,
        holdThreshold: TimeInterval = Constants.hotkeyHoldThresholdSeconds
    ) {
        self.permissionService = permissionService
        self.holdThreshold = holdThreshold
    }

    func start() async {
        let status = await permissionService.currentStatus()
        Logger.hotkey.info("HotkeyMonitor.start called — permission status: \(String(describing: status), privacy: .public)")
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
        let globalOK = globalMonitor != nil
        let localOK = localMonitor != nil
        Logger.hotkey.info("HotkeyMonitor started — global: \(globalOK, privacy: .public) local: \(localOK, privacy: .public)")
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
        commandDownAt = nil
        holdWorkItem?.cancel()
        holdWorkItem = nil
        if holdActive {
            holdActive = false
            Logger.hotkey.info("HotkeyMonitor trigger — ⌘ hold end")
            onHoldEnd?()
        }
    }
}
