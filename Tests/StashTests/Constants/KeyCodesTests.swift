// 변경 불가 단축키 keyCode 가 macOS 표준 UInt16 raw 값과 일치하는지 검증 — TASK-084 Phase 2 안전망
// macOS keyCode 는 영구 불변 contract. 값 변경 시 키 매칭 전부 깨짐.
import Testing
@testable import stash

@Suite("Constants.KeyCodes — macOS 표준 raw 값 일치")
struct KeyCodesTests {
    @Test("방향키 / Return / Numpad / ESC / D / Tab raw 값 검증")
    func keyCodesUnchanged() {
        #expect(Constants.KeyCodes.arrowUp == 126)
        #expect(Constants.KeyCodes.arrowDown == 125)
        #expect(Constants.KeyCodes.returnKey == 36)
        #expect(Constants.KeyCodes.numpadEnter == 76)
        #expect(Constants.KeyCodes.escape == 53)
        #expect(Constants.KeyCodes.keyD == 2)
        #expect(Constants.KeyCodes.tab == 48)
    }
}
