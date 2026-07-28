// KeyboardHintsView.hints 배열 구조 검증 — TASK-050 이동 단축키 3 hint → 1 통합 cell + pin 순서 재배치
// 단축키 라우팅 변경 X — 시각 표현만. PopoverShortcutStore 미주입 시 fallback 키 표시 검증.
// TASK-056 — 활성/비활성 popover 하단 갭 대칭 + hintBarVisible UserDefaults 기본값 회귀 가드 (`KeyboardHintsViewLayoutTests`).
@testable import stash
import Testing
import Foundation

@Suite("KeyboardHintsView — hints 배열 구조 (TASK-050)")
struct KeyboardHintsViewTests {

    @Test("hints.count == 8 — TASK-099 multiSelect (⌥C) 추가 후 8 개 cell")
    func hintsCount() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        #expect(view.hints.count == 8)
    }

    @Test("hints id 순서 — TASK-099 multiSelect (⌥C) paste 와 pin 사이 삽입 (선택 → 묶음 실행 학습 흐름)")
    func hintsOrder() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let ids = view.hints.map { $0.id }
        #expect(ids == ["move", "copy", "paste", "multiSelect", "pin", "clipDetail", "del", "delAll"])
    }

    @Test("move hint — parts.count == 3 (keys 3 그룹 연속, separator 없음)")
    func moveHintPartsCount() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let moveHint = view.hints[0]
        #expect(moveHint.id == "move")
        #expect(moveHint.parts.count == 3)
    }

    @Test("move hint — keys 배열 [↑↓] / [⌘↑↓] / [⌘⇧↑↓] (키캡 안 화살표 2 문자 동시)")
    func moveHintKeys() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let moveHint = view.hints[0]
        var keysByPart: [[String]] = []
        for part in moveHint.parts {
            if case .keys(let arr) = part {
                keysByPart.append(arr)
            }
        }
        #expect(keysByPart == [["↑↓"], ["⌘↑↓"], ["⌘⇧↑↓"]])
    }

    @Test("paste hint — Accessibility 권한 X 시 enabled=false (TASK-024 회귀 검증)")
    func pasteHintAccessibilityGate() {
        let granted = KeyboardHintsView(mode: .method1, accessibilityGranted: true)
        let revoked = KeyboardHintsView(mode: .method1, accessibilityGranted: false)
        let pasteGranted = granted.hints.first { $0.id == "paste" }
        let pasteRevoked = revoked.hints.first { $0.id == "paste" }
        #expect(pasteGranted?.enabled == true)
        #expect(pasteRevoked?.enabled == false)
    }

    @Test("move / copy / pin / del / delAll — enabled=true (Accessibility 권한 무관)")
    func nonPasteHintsAlwaysEnabled() {
        let view = KeyboardHintsView(mode: .method1, accessibilityGranted: false)
        for id in ["move", "copy", "pin", "del", "delAll"] {
            let hint = view.hints.first { $0.id == id }
            #expect(hint?.enabled == true, "\(id) hint enabled 기대 true")
        }
    }
}

// TASK-056 — hintBarVisible UserDefaults 기본값 회귀 가드.
// (시각 갭 대칭 정합 시도는 폐기 — 사용자 의도 부합 흐름: cliplist 차감 X, popover 가 위로 확장. 정합 보장은 `PopoverWindow._performRefreshFrame` 의 `NSHostingController.sizeThatFits(in:)` 동적 측정 흐름이 책임.)
@MainActor
@Suite("KeyboardHintsView — 레이아웃 정합 (TASK-056)")
struct KeyboardHintsViewLayoutTests {

    /// `StashApp.registerDefaults` / `HistoryPopover.@AppStorage default` / `SettingsViewModel default` / `ClipsViewModel.effectiveClipListHeightFromUserDefaults ?? true` 의 정합.
    @Test("hintBarVisible UserDefaults 미설정 → effectiveClipListHeightFromUserDefaults 가 hintBarVisible:true 와 동등")
    func hintBarVisibleDefaultIsTrue() {
        let prevRaw = UserDefaults.standard.object(forKey: "hintBarVisible")
        UserDefaults.standard.removeObject(forKey: "hintBarVisible")
        defer {
            if let prev = prevRaw as? Bool {
                UserDefaults.standard.set(prev, forKey: "hintBarVisible")
            } else {
                UserDefaults.standard.removeObject(forKey: "hintBarVisible")
            }
        }
        let hDefault = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 10, hasPinned: false)
        let n = UserDefaults.standard.integer(forKey: "clipsPerPage")
        let autoFit = UserDefaults.standard.bool(forKey: "autoFitClipListHeight")
        let hOn = ClipsViewModel.effectiveClipListHeight(
            visibleCount: 10,
            clipsPerPage: n,
            autoFit: autoFit,
            hasPinned: false,
            hintBarVisible: true
        )
        #expect(hDefault == hOn)
    }
}
