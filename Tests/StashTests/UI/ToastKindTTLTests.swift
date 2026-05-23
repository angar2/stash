// ToastKind.defaultTTL 4 case 정합 회귀 차단 (TASK-066 — UX-UI §6 알림 표 TTL kind별 통일)
import Testing
@testable import stash

@MainActor
@Suite("ToastKind.defaultTTL (TASK-066)")
struct ToastKindTTLTests {
    @Test("TASK-066 — success default TTL = 2.0s")
    func successTTL() {
        #expect(ToastKind.success.defaultTTL == 2.0)
    }

    @Test("TASK-066 — info default TTL = 2.5s")
    func infoTTL() {
        #expect(ToastKind.info.defaultTTL == 2.5)
    }

    @Test("TASK-066 — warn default TTL = 3.0s")
    func warnTTL() {
        #expect(ToastKind.warn.defaultTTL == 3.0)
    }

    @Test("TASK-066 — error default TTL = 4.0s")
    func errorTTL() {
        #expect(ToastKind.error.defaultTTL == 4.0)
    }
}
