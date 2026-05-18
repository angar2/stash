// 클릭 가능 요소에 손가락 cursor 표시 (TASK-030) — popover 안 paste / unpin / 삭제 / 환경설정 등 명시 액션 영역에 적용. `enabled` 게이트로 method3 보류 분기 정합.
import SwiftUI
import AppKit

extension View {
    /// hover 시 `NSCursor.pointingHand` push, exit 시 pop.
    /// `enabled == false` 시 cursor 표시 X — 직전에 push 된 cursor 가 남아있을 가능성 대비 pop() 호출 (안전망).
    func pointingHandCursor(enabled: Bool = true) -> some View {
        self.onHover { isHover in
            guard enabled else {
                NSCursor.pop()
                return
            }
            if isHover {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
