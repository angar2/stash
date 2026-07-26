// Pin 직접 paste 단축키 + 핀 명칭/값 편집의 *순수 계층* (TASK-098).
//
// 전역 hotkey 등록 · 시스템 이벤트 · SwiftUI 는 단위 테스트로 검증할 수 없다. 그래서 화면·시스템에 의존하지 않는
// 판정(순번 변환 / 기본 조합 / 대상 존재 / 표시 문자열 / 입력 정규화)만 여기로 분리해 테스트 가능하게 둔다.
// 반대로 *여기 통과 = 기능 동작* 은 아니다 — 실제 붙여넣기·커서·화면은 실기 검수가 유일한 근거다 (task Test Plan #15~#28).
import Foundation
import AppKit

enum PinPasteShortcutResolver {

    // MARK: - 순번 ↔ 식별자

    // 검수 정정 이후 `순번 → 배열 index` 변환(`pinIndex`)은 폐기했다. 순번은 *자리 번호*(`pin_slot`)이고
    // 배열 위치와 무관하므로, 그런 변환이 남아 있으면 앞자리가 빈 순간 다른 클립을 가리키는 결함이 다시 들어온다.
    // 대상 탐색은 `resolvePinTargetIndex(ordinal:slots:)` 하나만 쓴다.

    /// Pin 순번(1-based) → 단축키 식별자. 범위 밖이면 nil.
    static func shortcutID(forPinOrdinal ordinal: Int) -> PopoverShortcutID? {
        guard ordinal >= 1, ordinal <= PopoverShortcutID.pinPasteIDs.count else { return nil }
        return PopoverShortcutID.pinPasteIDs[ordinal - 1]
    }

    // MARK: - 기본 조합

    /// Pin 순번(1-based) 기본 조합 — `⌥⌘1`~`⌥⌘9`, `⌥⌘0`.
    /// 숫자 keyCode 는 순차가 아니므로 `Constants.KeyCodes.digitsPinOrder` 표를 그대로 인덱싱한다 (산술 생성 금지).
    static func defaultShortcut(forPinOrdinal ordinal: Int) -> PopoverShortcut? {
        let digits = Constants.KeyCodes.digitsPinOrder
        guard ordinal >= 1, ordinal <= digits.count else { return nil }
        return PopoverShortcut(keyCode: digits[ordinal - 1], modifiers: [.command, .option])
    }

    // MARK: - 대상 판정

    /// 눌린 순번이 가리키는 Pin 목록 index. **그 자리가 비어 있으면 nil** (= 무동작).
    /// 전역 단축키라 오타성 입력이 잦으므로 오류 표시 없이 무시하는 것이 정책 (FEATURES F-004).
    ///
    /// TASK-098 검수 정정 — 이전에는 `ordinal - 1` 을 그대로 배열 index 로 썼다. 그러면 앞자리를 핀 해제한 순간
    /// 뒤 항목이 당겨져 **같은 조합이 다른 클립을 붙여넣는다.** 이제 자리 번호(`pin_slot`)로 찾는다.
    /// - Parameter slots: `pinnedClips` 의 자리 번호 배열 (같은 순서·같은 길이).
    static func resolvePinTargetIndex(ordinal: Int, slots: [Int?]) -> Int? {
        guard ordinal >= 1, ordinal <= Constants.maxPinnedClips else { return nil }
        return slots.firstIndex { $0 == ordinal }
    }

    /// 새 핀에 배정할 가장 낮은 빈 자리. 자리가 없으면 nil (= 한도 초과).
    /// 저장 계층(`togglePin`)이 최종 판정하지만, 화면이 미리 판단해야 하는 자리(안내 문구 등)에서도 같은 규칙을 쓴다.
    static func lowestFreeSlot(occupied: [Int?]) -> Int? {
        let taken = Set(occupied.compactMap { $0 })
        return (1...Constants.maxPinnedClips).first { !taken.contains($0) }
    }

    // MARK: - 표시 문자열

    // 명칭 우선 표시(`displayTitle`)도 폐기했다. 사이드바·설정 행 모두 `normalizeAlias` 결과가 nil 인지로
    // *값을 그릴지 명칭을 그릴지* 를 분기하므로(서체·색이 다르다) 문자열 하나로 합치는 helper 는 쓰이지 않는다.

    /// 설정 PIN 단축키 행 타입 아이콘 SF Symbol — 클립 행과 같은 심볼 계열을 쓴다.
    /// 디렉토리 판정은 파일시스템 조회가 필요해 설정 행에서는 생략하고 `doc` 으로 둔다(Pin 사이드바는 `folder`/`doc` 구분 유지).
    /// 이미지 타입을 빼먹으면 이미지 핀이 *텍스트 아이콘* 으로 표시되므로 열거를 전부 덮는다.
    static func typeSymbol(type: ClipType, isMultiFile: Bool) -> String {
        switch type {
        case .image: return "photo"
        case .file:  return isMultiFile ? "doc.on.doc" : "doc"
        case .text:  return "text.alignleft"
        }
    }

    /// 조합 키캡 표시 문자열. 지정된 조합이 없으면 nil (키캡 미표시).
    static func keycapText(for shortcut: PopoverShortcut?) -> String? {
        shortcut?.displayText
    }

    /// 사용자가 기본값에서 바꾼 조합인지 — 키캡 색 분기(기본=옅게 / 변경=진하게)에 쓴다.
    static func isCustomized(shortcut: PopoverShortcut?, pinOrdinal ordinal: Int) -> Bool {
        guard let shortcut, let def = defaultShortcut(forPinOrdinal: ordinal) else { return false }
        return shortcut != def
    }

    // MARK: - 입력 정규화

    /// 명칭 입력 정규화 — 앞뒤 공백 제거 후 빈 문자면 nil(해제), 상한(40자) 초과면 절단.
    static func normalizeAlias(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > Constants.pinAliasMaxLength else { return trimmed }
        return String(trimmed.prefix(Constants.pinAliasMaxLength))
    }

    /// 값(본문) 편집 허용 여부 — 텍스트 클립만. 이미지·파일은 본문이 없어 대상 아님.
    static func isValueEditable(type: ClipType) -> Bool {
        type == .text
    }

    /// 값 입력 검증 — 빈 문자·공백만이면 nil(거부 → 수정 전 값 유지). 그 외는 *원문 그대로* 통과.
    /// 앞뒤 공백을 보존하는 이유: 들여쓰기·개행이 의미를 갖는 본문(코드·템플릿)이 많다. 상한도 두지 않는다.
    static func normalizeValue(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }
}
