// 단축키 모델 · 저장 계층 — 식별자(`PopoverShortcutID`) / 조합 모델(`PopoverShortcut`) / storage(`PopoverShortcutStore`).
// TASK-098 리팩토링 — `ShortcutsTab.swift` 가 1000줄을 넘겨 *탭 화면 / 저장 계층 / Recorder* 세 관심사를 한 파일에 담고 있었다.
// 화면 없이 쓰이는 계층(전역 등록 · 기본값 표 · 충돌 검사 · 앱 시작 시 default 등록)이라 화면 코드와 분리한다. 로직 변경 없는 이동.
//
// TASK-033 fix-2: SPM `setShortcut` 이 Carbon RegisterEventHotKey 글로벌 등록을 자동 트리거 → ⌘V/⌘C 같은 시스템 표준 단축키 매핑 시 시스템 paste/copy 무력화 + popover localMonitor 도달 X.
// → popover 안 6종 단축키는 SPM 사용 X. 자체 `PopoverShortcutStore` (UserDefaults JSON storage) + 자체 `PopoverShortcutRecorder` (NSEvent monitor 기반 NSViewRepresentable).
//   전역 등록 대상은 `.popoverOpen` (글로벌 진입 본질) + TASK-098 Pin 10종 (어디서나 동작이 본질) 뿐이다.
import Foundation
import AppKit
import KeyboardShortcuts
import OSLog

// MARK: - SPM Name (.popoverOpen 전용 — TASK-032 글로벌 진입)

extension KeyboardShortcuts.Name {
    // TASK-032 — popover 진입용 글로벌 단축키 (Carbon RegisterEventHotKey 기반, Accessibility 권한 무관).
    // TASK-065 — default ⌘⇧V → ⌘⇧C (사용자 혼동 회피, PopoverShortcutStore.defaults 진실 소스).
    static let popoverOpen = Self("stash.popoverOpen")

    // TASK-098 — Pin 직접 paste 전역 단축키 (Pin 1~10번). `.popoverOpen` 과 동일한 Carbon 글로벌 등록 경로.
    // *전역 동작이 본질* 이므로 popover 안 6종(자체 store)과 달리 SPM 을 쓴다.
    // index 0 = Pin 1번 … index 9 = Pin 10번. raw 이름은 영구 불변 (변경 시 사용자 설정값 손실).
    static let pinPaste: [Self] = (1...Constants.maxPinnedClips).map { Self("stash.pinPaste\($0)") }
}

// MARK: - PopoverShortcut model + Store (TASK-033 fix-2)

/// 단축키 식별자.
/// - **전역 등록 (SPM `KeyboardShortcuts.Name` Carbon hotkey)**: `.popoverOpen` (글로벌 진입 본질) + `.pinPaste1`~`.pinPaste10` (TASK-098 — 어디서나 동작이 본질).
/// - **popover localMonitor 매칭 (Carbon 등록 회피)**: 나머지 6종.
enum PopoverShortcutID: String, CaseIterable, Sendable {
    case popoverOpen
    case copy
    case paste
    case pinToggle
    case pinSidebarToggle
    case deleteOne
    case deleteAll
    // TASK-098 — Pin 직접 paste (Pin 1~10번). raw value 는 `pinPaste<순번>` 규약 — `pinOrdinal` 이 이 규약을 파싱한다.
    case pinPaste1, pinPaste2, pinPaste3, pinPaste4, pinPaste5
    case pinPaste6, pinPaste7, pinPaste8, pinPaste9, pinPaste10

    /// 사용자 라벨 i18n 키.
    /// TASK-098 — Pin 10종은 설정 행에서 고정 문구가 아니라 *명칭(없으면 값)* 을 표시하므로 본 키는 접근성/폴백 용도.
    var labelKey: String {
        switch self {
        case .popoverOpen: return "shortcuts.popoverOpen"
        case .copy: return "shortcuts.copy"
        case .paste: return "shortcuts.paste"
        case .pinToggle: return "shortcuts.pinToggle"
        case .pinSidebarToggle: return "shortcuts.pinSidebarToggle"
        case .deleteOne: return "shortcuts.deleteOne"
        case .deleteAll: return "shortcuts.deleteAll"
        // TASK-098 — `default:` 를 쓰지 않는다. 열거에 새 항목이 붙었을 때 조용히 *핀 붙여넣기* 라벨로 새는 대신 컴파일 에러로 드러나야 한다.
        case .pinPaste1, .pinPaste2, .pinPaste3, .pinPaste4, .pinPaste5,
             .pinPaste6, .pinPaste7, .pinPaste8, .pinPaste9, .pinPaste10:
            return "shortcuts.pinPaste"
        }
    }

    /// 사용자에게 *어느 항목인지* 알려야 하는 자리(중복 조합 토스트 등)의 라벨.
    /// TASK-098 — Pin 10종은 `labelKey` 가 모두 같아서 순번을 붙이지 않으면 어느 번호와 겹쳤는지 알 수 없다.
    var conflictLabel: String {
        if let ordinal = pinOrdinal { return "\(L10n(labelKey)) \(ordinal)" }
        return L10n(labelKey)
    }

    /// TASK-098 — Pin 순번 (1-based). Pin 직접 paste 단축키가 아니면 nil.
    var pinOrdinal: Int? {
        let prefix = "pinPaste"
        guard rawValue.hasPrefix(prefix), let n = Int(rawValue.dropFirst(prefix.count)) else { return nil }
        return n
    }

    /// TASK-098 — Pin 직접 paste 10종을 순번 오름차순으로. 설정 화면·전역 등록이 공통 참조하는 순서 진실 소스.
    static let pinPasteIDs: [PopoverShortcutID] = allCases
        .compactMap { id in id.pinOrdinal.map { (id, $0) } }
        .sorted { $0.1 < $1.1 }
        .map(\.0)

    /// TASK-098 — SPM Carbon 전역 등록 대상이면 그 `Name`, 아니면 nil (= popover localMonitor 매칭 대상).
    /// `PopoverShortcutStore` 의 저장·조회 분기 + 매 실행 강제 초기화 제외 판정이 본 프로퍼티 하나를 기준으로 삼는다.
    var globalName: KeyboardShortcuts.Name? {
        if self == .popoverOpen { return .popoverOpen }
        guard let n = pinOrdinal, n >= 1, n <= KeyboardShortcuts.Name.pinPaste.count else { return nil }
        return KeyboardShortcuts.Name.pinPaste[n - 1]
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
        // 전역 등록 대상(.popoverOpen + TASK-098 Pin 10종)은 SPM 이 단일 진실 소스 (Carbon 글로벌 hotkey).
        if let name = id.globalName {
            guard let spm = KeyboardShortcuts.getShortcut(for: name) else { return nil }
            return PopoverShortcut(keyCode: UInt16(spm.carbonKeyCode), modifiers: spm.modifiers)
        }
        guard let data = UserDefaults.standard.data(forKey: prefix + id.rawValue),
              let shortcut = try? JSONDecoder().decode(PopoverShortcut.self, from: data) else {
            return nil
        }
        return shortcut
    }

    static func set(_ shortcut: PopoverShortcut, for id: PopoverShortcutID) {
        // 전역 등록 대상(.popoverOpen + TASK-098 Pin 10종)은 SPM Carbon 등록.
        if let name = id.globalName {
            let key = KeyboardShortcuts.Key(rawValue: Int(shortcut.keyCode))
            KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(key, modifiers: shortcut.modifiers), for: name)
            Logger.ui.info("PopoverShortcutStore set \(id.rawValue, privacy: .public) (SPM) = \(shortcut.displayText, privacy: .public)")
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
    /// TASK-098 — Pin 1~10번 default `⌥⌘1`~`⌥⌘9`, `⌥⌘0`. `⌘`+숫자를 기본값으로 두지 않는 이유:
    /// 전역(Carbon) 등록이라 `⌘1`~`⌘9` 를 기본값으로 잡으면 Xcode 네비게이터 전환 · 브라우저 탭 이동 ·
    /// Finder 보기 방식(`⌘1`~`⌘4`)이 설치 직후부터 무력화된다 (TASK-033 fix-2 의 시스템 paste/copy 무력화와 동일 실패 유형).
    /// 사용자가 설정에서 `⌘1` 로 직접 바꾸는 것은 허용.
    static let defaults: [PopoverShortcutID: PopoverShortcut] = {
        var table: [PopoverShortcutID: PopoverShortcut] = [
            .popoverOpen:      PopoverShortcut(keyCode: 8, modifiers: [.command, .shift]),       // ⌘⇧C (TASK-065)
            .copy:             PopoverShortcut(keyCode: 8, modifiers: [.command]),               // ⌘C
            .paste:            PopoverShortcut(keyCode: 9, modifiers: [.command]),               // ⌘V
            .pinToggle:        PopoverShortcut(keyCode: 35, modifiers: [.command]),              // ⌘P
            .pinSidebarToggle: PopoverShortcut(keyCode: 11, modifiers: [.command]),              // ⌘B
            .deleteOne:        PopoverShortcut(keyCode: 51, modifiers: [.command]),              // ⌘⌫
            .deleteAll:        PopoverShortcut(keyCode: 51, modifiers: [.command, .shift])       // ⇧⌘⌫
        ]
        // 숫자 keyCode 는 순차가 아님 — Constants.KeyCodes.digitsPinOrder 표를 그대로 사용 (산술 생성 금지).
        for (idx, id) in PopoverShortcutID.pinPasteIDs.enumerated()
        where idx < Constants.KeyCodes.digitsPinOrder.count {
            table[id] = PopoverShortcut(
                keyCode: Constants.KeyCodes.digitsPinOrder[idx],
                modifiers: [.command, .option]
            )
        }
        return table
    }()

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
        // TASK-098 — 전역 등록 대상(.popoverOpen + Pin 10종)은 본 강제 reset에서 **제외**. 이들은 SPM 저장이라 위 prefix 키와 무관하기도 하고,
        // 무엇보다 Pin 조합은 사용자가 외워서 쓰는 값이라 매 실행 초기화되면 기능 자체가 성립하지 않는다.
        for id in PopoverShortcutID.allCases where id.globalName == nil {
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

    /// 전 항목 default 복원 (기본 7종 + TASK-098 Pin 10종). 설정 탭 *전체 되돌리기* 버튼.
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
