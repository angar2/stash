// 단축키 Recorder — SPM `KeyboardShortcuts.Recorder` 대신 쓰는 자체 NSView (TASK-033 fix-2 / TASK-083).
// TASK-098 리팩토링 — `ShortcutsTab.swift` 에서 분리. AppKit 이벤트 monitor 계층이라 탭 화면과 관심사가 다르다. 로직 변경 없는 이동.
import SwiftUI
import AppKit
import OSLog

// MARK: - PopoverShortcutRecorder (자체 NSView — NSEvent monitor 기반)

/// 자체 단축키 Recorder. SPM `KeyboardShortcuts.Recorder` 사용 X (Carbon 등록 회피).
/// 클릭 시 *recording mode* 진입 → NSEvent.addLocalMonitorForEvents 등록 → 다음 keyDown 캡쳐 → onChange 콜백 → recording 종료.
@MainActor
final class PopoverShortcutRecorderViewCocoa: NSView {
    let id: PopoverShortcutID
    let onChange: (PopoverShortcut?) -> Void

    private let label: NSTextField
    /// TASK-083 — keyDown / mouseDown 두 monitor 분리. focus-out 패턴 (Recorder 영역 바깥 클릭 시 stop) 위해 mouseDown localMonitor 신규.
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    /// TASK-083 — Settings 윈도우 비활성 시 자동 stop. localMonitor 가 잡지 못하는 외부 앱/Dock 활성 케이스 보완.
    nonisolated(unsafe) private var resignKeyObserver: NSObjectProtocol?
    private var isRecording: Bool = false
    /// TASK-082 Phase 9 (P3) — Swift 6 strict concurrency nonisolated deinit 안 property 접근 위해 `nonisolated(unsafe)` 박음. NSObjectProtocol 자체 Sendable 부합 X, NotificationCenter.removeObserver 는 thread-safe (Foundation 표준).
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    /// TASK-065 — hover state. NSTrackingArea 로 mouseEntered/exited 감지 → borderColor + bg 색 분기.
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    init(id: PopoverShortcutID, onChange: @escaping (PopoverShortcut?) -> Void) {
        self.id = id
        self.onChange = onChange
        self.label = NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        self.wantsLayer = true
        self.layer?.cornerRadius = 5
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor.separatorColor.cgColor
        self.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateLabel()

        // store 변경 시 label 자동 갱신. notification.userInfo capture 회피 — id raw 만 추출 후 클로저 외부 capture.
        let myId = self.id.rawValue
        observer = NotificationCenter.default.addObserver(
            forName: .popoverShortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changedId = notification.userInfo?["id"] as? String
            Task { @MainActor [weak self] in
                guard let self, changedId == myId else { return }
                self.updateLabel()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // TASK-082 Phase 9 (P3) — 명시 cleanup 박음. PreferencesWindow 가 lazy 생성 + 재사용 (`isReleasedWhenClosed = false`) 라 실제 deinit 흐름은 *process termination* 만 — 동작 영향 0 이지만 Swift 정합.
    // TASK-083 — resignKeyObserver 도 cleanup. NSEvent monitor (keyMonitor/mouseMonitor) 는 recording 활성 상태 view 소멸 케이스에만 잔존 — 정상 흐름 (didResignKey → stopRecording) 자연 정리, process termination 시 시스템 정리.
    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // TASK-065 — NSTrackingArea hover 감지 (Recorder 보더/배경 색 분기).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateLabel()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateLabel()
    }

    private func startRecording() {
        isRecording = true
        updateLabel()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return Self.handleKeyDown(event: event, recorder: self) ? nil : event
        }
        // TASK-083 — focus-out (Recorder 영역 바깥 클릭) 시 stop. 이벤트는 *그대로 전파* (return event) → 다른 Recorder 클릭 시 B start 자연 흐름 보장.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let recorderBoundsInWindow = self.convert(self.bounds, to: nil)
            if Self.isFocusOutClick(
                eventLocationInWindow: event.locationInWindow,
                eventWindow: event.window,
                recorderWindow: self.window,
                recorderBoundsInWindow: recorderBoundsInWindow
            ) {
                Logger.ui.info("PopoverShortcutRecorder \(self.id.rawValue, privacy: .public) — outside mouseDown → stop")
                self.stopRecording()
            }
            return event
        }
        // TASK-083 — Settings 윈도우 비활성 (Dock / 다른 앱 활성화) 시 자동 stop. localMonitor 가 잡지 못하는 외부 경로 보완.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self.window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                Logger.ui.info("PopoverShortcutRecorder \(self.id.rawValue, privacy: .public) — window didResignKey → stop")
                self.stopRecording()
            }
        }
        Logger.ui.info("PopoverShortcutRecorder \(self.id.rawValue, privacy: .public) — recording started")
    }

    /// TASK-083 — Recorder 영역 외부 클릭 판정 (localMonitor 핵심 로직 단위 테스트 가능 형태로 분리). 같은 윈도우 안 + Recorder bounds 밖 = focus-out trigger.
    /// - eventLocationInWindow: `NSEvent.locationInWindow` (윈도우 좌표계)
    /// - eventWindow: `NSEvent.window` — 이벤트 발생 윈도우
    /// - recorderWindow: Recorder view 가 박힌 윈도우
    /// - recorderBoundsInWindow: Recorder bounds 를 윈도우 좌표계로 변환한 rect
    @MainActor
    internal static func isFocusOutClick(
        eventLocationInWindow: CGPoint,
        eventWindow: NSWindow?,
        recorderWindow: NSWindow?,
        recorderBoundsInWindow: CGRect
    ) -> Bool {
        guard eventWindow === recorderWindow else { return false }
        return !recorderBoundsInWindow.contains(eventLocationInWindow)
    }

    @MainActor
    private static func handleKeyDown(event: NSEvent, recorder: PopoverShortcutRecorderViewCocoa) -> Bool {
        // ESC → 취소 (변경 X)
        if event.keyCode == Constants.KeyCodes.escape {
            recorder.stopRecording()
            return true
        }
        // 단축키 추출 — modifier 없으면 modifier 검증 실패 콜백
        guard let shortcut = PopoverShortcut.from(event: event) else {
            // modifier 없음 — onChange(nil-equivalent invalid) 처리는 호출처에 위임. 여기선 *recording 유지* + onChange(invalid) 호출.
            recorder.onChange(PopoverShortcut(keyCode: event.keyCode, modifiers: NSEvent.ModifierFlags(rawValue: 0)))
            // recording 유지 (사용자 재입력 기회). 단 onChange 호출처에서 토스트 + revert.
            return true
        }
        recorder.onChange(shortcut)
        recorder.stopRecording()
        return true
    }

    private func stopRecording() {
        isRecording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        updateLabel()
        Logger.ui.info("PopoverShortcutRecorder \(self.id.rawValue, privacy: .public) — recording stopped")
    }

    private func updateLabel() {
        if isRecording {
            label.stringValue = L10n("shortcuts.recorder.placeholder")
            label.textColor = .secondaryLabelColor
            self.layer?.borderColor = NSColor.controlAccentColor.cgColor
            self.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        } else {
            let shortcut = PopoverShortcutStore.get(id)
            label.stringValue = shortcut?.displayText ?? L10n("shortcuts.recorder.change")
            label.textColor = .labelColor
            // TASK-065 — hover 시 보더 진하게 + bg opacity 증가 (시각 피드백).
            self.layer?.borderColor = (isHovered ? NSColor.labelColor.withAlphaComponent(0.35) : NSColor.separatorColor).cgColor
            self.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(isHovered ? 0.85 : 0.5).cgColor
        }
    }
}

struct PopoverShortcutRecorder: NSViewRepresentable {
    let id: PopoverShortcutID
    let onChange: (PopoverShortcut?) -> Void

    func makeNSView(context: Context) -> PopoverShortcutRecorderViewCocoa {
        PopoverShortcutRecorderViewCocoa(id: id, onChange: onChange)
    }

    func updateNSView(_ nsView: PopoverShortcutRecorderViewCocoa, context: Context) {}
}
