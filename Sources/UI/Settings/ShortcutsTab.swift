// 설정 단축키 탭 — 환경설정 노출 7항목 (보관함 열기 / 복사 / 붙여넣기 / 핀 고정·해제 / 핀 목록 열기·닫기 / 선택 삭제 / 전체 삭제)
// TASK-033 fix-2: SPM `setShortcut` 이 Carbon RegisterEventHotKey 글로벌 등록을 자동 트리거 → ⌘V/⌘C 같은 시스템 표준 단축키 매핑 시 시스템 paste/copy 무력화 + popover localMonitor 도달 X.
// → popover 안 6종 단축키는 SPM 사용 X. 자체 `PopoverShortcutStore` (UserDefaults JSON storage) + 자체 `PopoverShortcutRecorder` (NSEvent monitor 기반 NSViewRepresentable). `.popoverOpen` 만 SPM 유지 (글로벌 진입 hotkey 본질).
import SwiftUI
import AppKit
import KeyboardShortcuts
import OSLog

// MARK: - SPM Name (.popoverOpen 전용 — TASK-032 글로벌 진입)

extension KeyboardShortcuts.Name {
    // TASK-032 — popover 진입용 글로벌 단축키 (Carbon RegisterEventHotKey 기반, Accessibility 권한 무관).
    // TASK-065 — default ⌘⇧V → ⌘⇧C (사용자 혼동 회피, PopoverShortcutStore.defaults 진실 소스).
    static let popoverOpen = Self("stash.popoverOpen")
}

// MARK: - PopoverShortcut model + Store (TASK-033 fix-2)

/// 단축키 식별자. `.popoverOpen` 만 SPM `KeyboardShortcuts.Name` Carbon 글로벌 hotkey 등록 (글로벌 진입 본질). 나머지 6종은 popover localMonitor 매칭 (Carbon 등록 회피).
enum PopoverShortcutID: String, CaseIterable, Sendable {
    case popoverOpen
    case copy
    case paste
    case pinToggle
    case pinSidebarToggle
    case deleteOne
    case deleteAll

    /// 사용자 라벨 i18n 키.
    var labelKey: String {
        switch self {
        case .popoverOpen: return "shortcuts.popoverOpen"
        case .copy: return "shortcuts.copy"
        case .paste: return "shortcuts.paste"
        case .pinToggle: return "shortcuts.pinToggle"
        case .pinSidebarToggle: return "shortcuts.pinSidebarToggle"
        case .deleteOne: return "shortcuts.deleteOne"
        case .deleteAll: return "shortcuts.deleteAll"
        }
    }
}

/// popover 안 단축키 모델 — `keyCode` + meaningful modifier (`.command/.shift/.option/.control`) raw value 저장.
struct PopoverShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiersRawValue: UInt

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiersRawValue) }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        let meaningful: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        self.modifiersRawValue = modifiers.intersection(meaningful).rawValue
    }

    /// `NSEvent` 에서 단축키 추출. modifier 없으면 nil (modifier 검증).
    static func from(event: NSEvent) -> PopoverShortcut? {
        let meaningful: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let mods = event.modifierFlags.intersection(meaningful)
        guard !mods.isEmpty else { return nil }
        return PopoverShortcut(keyCode: event.keyCode, modifiers: mods)
    }

    /// `NSEvent` 와 매칭. `keyCode` + meaningful modifier raw value 정확 일치 (OptionSet `==` 비교 대신 rawValue 직접 비교로 robust).
    func matches(event: NSEvent) -> Bool {
        let meaningful: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventMods = event.modifierFlags.intersection(meaningful).rawValue
        let match = event.keyCode == keyCode && eventMods == modifiersRawValue
        if event.keyCode == keyCode {
            Logger.ui.debug("PopoverShortcut.matches keyCode=\(self.keyCode) self.mods=\(self.modifiersRawValue) event.mods=\(eventMods) match=\(match)")
        }
        return match
    }

    /// 시각 표시 (⌘⇧⌥⌃ + key character).
    var displayText: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += Self.keyDisplay(for: keyCode)
        return s
    }

    /// `keyCode` → 키 라벨 매핑. macOS Carbon `kVK_*` 기준. 일반 키 + 화이트 화살표 / Delete 등 특수 키.
    static func keyDisplay(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"; case 11: return "B"; case 8: return "C"; case 2: return "D"
        case 14: return "E"; case 3: return "F"; case 5: return "G"; case 4: return "H"
        case 34: return "I"; case 38: return "J"; case 40: return "K"; case 37: return "L"
        case 46: return "M"; case 45: return "N"; case 31: return "O"; case 35: return "P"
        case 12: return "Q"; case 15: return "R"; case 1: return "S"; case 17: return "T"
        case 32: return "U"; case 9: return "V"; case 13: return "W"; case 7: return "X"
        case 16: return "Y"; case 6: return "Z"
        case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
        case 23: return "5"; case 22: return "6"; case 26: return "7"; case 28: return "8"
        case 25: return "9"; case 29: return "0"
        case 51: return "⌫"        // Backspace
        case 117: return "⌦"       // Forward Delete
        case 36: return "↩"        // Return
        case 76: return "⌤"        // Enter
        case 48: return "⇥"        // Tab
        case 49: return "Space"
        case 53: return "⎋"        // Escape
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"; case 118: return "F4"
        case 96: return "F5"; case 97: return "F6"; case 98: return "F7"; case 100: return "F8"
        case 101: return "F9"; case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        case 27: return "-"; case 24: return "="; case 33: return "["; case 30: return "]"
        case 41: return ";"; case 39: return "'"; case 43: return ","; case 47: return "."
        case 44: return "/"; case 42: return "\\"; case 50: return "`"
        default: return "?"
        }
    }
}

/// 단축키 storage.
/// - `.popoverOpen` — SPM `KeyboardShortcuts.Shortcut` 진실 소스 (Carbon 글로벌 hotkey 등록 필수, 글로벌 진입 본질).
/// - 나머지 6종 — 자체 UserDefaults JSON storage (Carbon 글로벌 등록 회피 — 시스템 표준 단축키 무력화 방지).
enum PopoverShortcutStore {
    private static let prefix = "stash.popoverShortcut."

    static func get(_ id: PopoverShortcutID) -> PopoverShortcut? {
        if id == .popoverOpen {
            // .popoverOpen 은 SPM 단일 진실 소스 (Carbon 글로벌 hotkey)
            guard let spm = KeyboardShortcuts.getShortcut(for: .popoverOpen) else { return nil }
            return PopoverShortcut(keyCode: UInt16(spm.carbonKeyCode), modifiers: spm.modifiers)
        }
        guard let data = UserDefaults.standard.data(forKey: prefix + id.rawValue),
              let shortcut = try? JSONDecoder().decode(PopoverShortcut.self, from: data) else {
            return nil
        }
        return shortcut
    }

    static func set(_ shortcut: PopoverShortcut, for id: PopoverShortcutID) {
        if id == .popoverOpen {
            // .popoverOpen 은 SPM Carbon 등록 (글로벌 진입 hotkey)
            let key = KeyboardShortcuts.Key(rawValue: Int(shortcut.keyCode))
            KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(key, modifiers: shortcut.modifiers), for: .popoverOpen)
            Logger.ui.info("PopoverShortcutStore set .popoverOpen (SPM) = \(shortcut.displayText, privacy: .public)")
            NotificationCenter.default.post(name: .popoverShortcutDidChange, object: nil, userInfo: ["id": id.rawValue])
            return
        }
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: prefix + id.rawValue)
        Logger.ui.info("PopoverShortcutStore set \(id.rawValue, privacy: .public) = \(shortcut.displayText, privacy: .public)")
        NotificationCenter.default.post(name: .popoverShortcutDidChange, object: nil, userInfo: ["id": id.rawValue])
    }

    /// default 단축키 매핑 (단일 진실 소스). 사용자 변경 없을 시 fallback.
    /// TASK-065 — `.popoverOpen` default `⌘⇧V` (keyCode 9) → `⌘⇧C` (keyCode 8). 시스템 paste 키와 modifier 겹쳐 사용자 혼동 회피 + 시스템 copy `⌘C` 에 ⇧ 1 modifier 추가가 학습 부담 최소.
    static let defaults: [PopoverShortcutID: PopoverShortcut] = [
        .popoverOpen:      PopoverShortcut(keyCode: 8, modifiers: [.command, .shift]),       // ⌘⇧C (TASK-065)
        .copy:             PopoverShortcut(keyCode: 8, modifiers: [.command]),               // ⌘C
        .paste:            PopoverShortcut(keyCode: 9, modifiers: [.command]),               // ⌘V
        .pinToggle:        PopoverShortcut(keyCode: 35, modifiers: [.command]),              // ⌘P
        .pinSidebarToggle: PopoverShortcut(keyCode: 11, modifiers: [.command]),              // ⌘B
        .deleteOne:        PopoverShortcut(keyCode: 51, modifiers: [.command]),              // ⌘⌫
        .deleteAll:        PopoverShortcut(keyCode: 51, modifiers: [.command, .shift])       // ⇧⌘⌫
    ]

    /// 첫 실행 + reset 후 next launch — 미등록 default 등록.
    static func registerDefaultsIfNeeded() {
        // TASK-033 fix-2 cleanup — 이전 TASK-033 v1 시도로 SPM (`KeyboardShortcuts_stash.*`) 에 박힌 잔존 키 정리. .popoverOpen 외 6종 SPM 사용 폐기 정합.
        let legacySpmKeys = [
            "KeyboardShortcuts_stash.copy",
            "KeyboardShortcuts_stash.paste",
            "KeyboardShortcuts_stash.pinToggle",
            "KeyboardShortcuts_stash.pinSidebarToggle",
            "KeyboardShortcuts_stash.deleteOne",
            "KeyboardShortcuts_stash.deleteAll"
        ]
        for key in legacySpmKeys {
            if UserDefaults.standard.object(forKey: key) != nil {
                UserDefaults.standard.removeObject(forKey: key)
                Logger.ui.info("PopoverShortcutStore cleanup — legacy SPM key removed: \(key, privacy: .public)")
            }
        }

        // TASK-033 fix-5 — 6종 자체 store 매 launch 강제 reset. marker 없이 매번 reset → 사용자 변경값 매 launch 잃음 (베타 단계 정합. 이후 stable 빌드에서 marker 도입 또는 폐기).
        for id in PopoverShortcutID.allCases where id != .popoverOpen {
            UserDefaults.standard.removeObject(forKey: prefix + id.rawValue)
        }

        for id in PopoverShortcutID.allCases {
            if get(id) == nil, let def = defaults[id] {
                set(def, for: id)
                Logger.ui.info("PopoverShortcutStore default registered: \(id.rawValue, privacy: .public)")
            }
        }
    }

    /// 항목별 default 복원.
    static func reset(_ id: PopoverShortcutID) {
        if let def = defaults[id] {
            set(def, for: id)
        }
    }

    /// 7항목 모두 default 복원.
    static func resetAll() {
        for id in PopoverShortcutID.allCases {
            if let def = defaults[id] {
                set(def, for: id)
            }
        }
    }
}

extension Notification.Name {
    static let popoverShortcutDidChange = Notification.Name("stash.popoverShortcutDidChange")
}

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

// MARK: - ShortcutsTab

struct ShortcutsTab: View {
    @Bindable var viewModel: SettingsViewModel
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 강조 텍스트 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue
    /// TASK-073 — 앱 언어 변경 시 body 재평가 → 모든 i18n 키 lookup 새 언어.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        let _ = accentColorModeRaw  // SwiftUI 의존성 등록
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 14) {
            settingsCard {
                VStack(spacing: 0) {
                    let allIds = PopoverShortcutID.allCases
                    ForEach(Array(allIds.enumerated()), id: \.element) { idx, id in
                        popoverShortcutRow(id: id)
                        if idx < allIds.count - 1 {
                            Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                // TASK-065 — *전체 되돌리기* 카드형 버튼. hover 시 배경 톤.
                HoverFillCardButton(
                    action: { viewModel.resetAllShortcuts() },
                    fill: DesignTokens.Colors.settingsCardBg,
                    fillHover: DesignTokens.Colors.settingsCardBgHover
                ) {
                    Text(L10n("shortcuts.resetAll"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }

            Text(L10n("shortcuts.note"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func popoverShortcutRow(id: PopoverShortcutID) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L10n(id.labelKey))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
            // TASK-065 — 전체 삭제 항목 라벨 우측에 secondary 컬러 부가 설명. 라벨 자체를 단순화(*전체 삭제*) 하고 핀 제외 정책은 부가 라인으로 분리.
            if id == .deleteAll {
                Text(L10n("shortcuts.deleteAll.note"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
            Spacer()
            PopoverShortcutRecorder(id: id) { newShortcut in
                viewModel.handlePopoverShortcutChange(id: id, newShortcut: newShortcut, allIds: PopoverShortcutID.allCases)
            }
            .frame(width: 100, height: 22)
            // TASK-065 — 항목별 *되돌리기* 텍스트 hover 시 accent 진하게.
            _ResetShortcutItemButton(action: { viewModel.resetPopoverShortcut(id: id) })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - TASK-065 hover-aware sub-views

@MainActor
private struct _ResetShortcutItemButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(L10n("shortcuts.resetItem"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.accent.opacity(isHovered ? 1.0 : 0.70))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
