// PopoverPanel.findFirstTextField — popover open 시 검색바 first responder 진입 회귀 차단 단위 테스트 (TASK-044)
import Testing
import AppKit
@testable import stash

@MainActor
@Suite("PopoverPanel.findFirstTextField (TASK-044)")
struct PopoverWindowFirstResponderTests {
    /// TASK-044 — 빈 NSView (NSTextField 없음) → nil 반환. findFirstTextField 의 base case.
    @Test("TASK-044 — 빈 NSView 는 nil 반환")
    func returnsNilForEmptyView() {
        let view = NSView()
        let result = PopoverPanel.findFirstTextField(in: view)
        #expect(result == nil, "NSTextField 가 없는 NSView 는 nil 반환해야 함")
    }

    /// TASK-044 — 단일 NSTextField → 동일 NSTextField 반환. findFirstTextField 의 self-match case.
    @Test("TASK-044 — 단일 NSTextField 는 자기 자신 반환")
    func returnsSelfForSingleTextField() {
        let textField = NSTextField()
        let result = PopoverPanel.findFirstTextField(in: textField)
        #expect(result === textField, "전달된 NSTextField 가 그대로 반환되어야 함")
    }

    /// TASK-044 — 중첩 트리 (NSView > NSView > NSTextField) → 깊은 NSTextField 반환. 재귀 탐색 정확성. PopoverWindow.showInternal 의 panel.contentView → visualEffectView → NSHostingView → ... → NSTextField 트리에 대응.
    @Test("TASK-044 — 중첩 NSView 트리에서 깊은 NSTextField 반환")
    func returnsLeafTextFieldFromNestedTree() {
        let root = NSView()
        let mid = NSView()
        let leaf = NSTextField()
        mid.addSubview(leaf)
        root.addSubview(mid)
        let result = PopoverPanel.findFirstTextField(in: root)
        #expect(result === leaf, "중첩된 트리에서 깊은 NSTextField 가 반환되어야 함")
    }

    /// TASK-044 — nil 입력 → nil 반환. guard 분기 검증.
    @Test("TASK-044 — nil 입력은 nil 반환")
    func returnsNilForNilInput() {
        let result = PopoverPanel.findFirstTextField(in: nil)
        #expect(result == nil, "nil 입력은 nil 반환해야 함 (guard 분기)")
    }

    /// TASK-044 — 형제 트리에서 첫 매칭 우선. subviews 순회 순서 정합 (depth-first / index 0 부터).
    @Test("TASK-044 — 형제 노드 중 가장 먼저 추가된 NSTextField 반환")
    func returnsFirstSiblingTextField() {
        let root = NSView()
        let firstTextField = NSTextField()
        let secondTextField = NSTextField()
        root.addSubview(firstTextField)
        root.addSubview(secondTextField)
        let result = PopoverPanel.findFirstTextField(in: root)
        #expect(result === firstTextField, "subviews 순서상 먼저 추가된 NSTextField 가 반환되어야 함")
    }
}
