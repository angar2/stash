// HoverTooltipController 상태 머신 검증 (TASK-079 — `.help()` SwiftUI tooltip 우회 인프라)
//
// enter(delay:) → 지연 후 isVisible=true / exit() → pending task 취소 + isVisible=false 즉시 / 연속 enter()
// pending 재시작. popover not-key panel 환경에서 SwiftUI overlay 자체 호버 툴팁을 박는 핵심 로직.
import Testing
@testable import stash

@MainActor
@Suite("HoverTooltipController (TASK-079)")
struct HoverTooltipControllerTests {

    /// 짧은 delay (50ms) 로 테스트 실행 시간 단축. pastDelayWait 는 Task scheduling 지연 흡수 위해 delay 4배 (200ms).
    private let shortDelay: Double = 0.05
    private let pastDelayWait: UInt64 = 200_000_000  // 200 ms — delay 4배 (Task scheduling race 흡수)
    private let beforeDelayWait: UInt64 = 20_000_000 // 20 ms — delay 도달 전

    @Test("enter(delay:) 호출 후 delay 경과 → isVisible == true")
    func enterShowsAfterDelay() async throws {
        let controller = HoverTooltipController()
        #expect(controller.isVisible == false)

        controller.enter(delay: shortDelay)
        try await Task.sleep(nanoseconds: pastDelayWait)

        #expect(controller.isVisible == true)
    }

    @Test("enter(delay:) 호출 후 delay 경과 전 exit() → isVisible == false 유지 (pending task 취소)")
    func exitBeforeDelayCancelsPending() async throws {
        let controller = HoverTooltipController()

        controller.enter(delay: shortDelay)
        try await Task.sleep(nanoseconds: beforeDelayWait)
        controller.exit()

        // delay 통과 시점까지 추가 대기 — 만약 cancel 이 안 됐으면 isVisible=true 박힘
        try await Task.sleep(nanoseconds: pastDelayWait)

        #expect(controller.isVisible == false)
    }

    @Test("enter(delay:) 직후 (대기 전) isVisible == false")
    func enterDoesNotShowImmediately() {
        let controller = HoverTooltipController()

        controller.enter(delay: shortDelay)

        #expect(controller.isVisible == false)
    }

    @Test("exit() 호출 후 isVisible == false 즉시 반영")
    func exitClearsImmediately() async throws {
        let controller = HoverTooltipController()

        controller.enter(delay: shortDelay)
        try await Task.sleep(nanoseconds: pastDelayWait)
        #expect(controller.isVisible == true)

        controller.exit()
        // 추가 await 없이 즉시 반영
        #expect(controller.isVisible == false)
    }

    @Test("연속 enter(delay:) 호출 시 마지막 호출 기준 delay 후 isVisible == true (이전 pending 취소 + 신규 task)")
    func consecutiveEnterRestartsTimer() async throws {
        let controller = HoverTooltipController()

        controller.enter(delay: shortDelay)
        try await Task.sleep(nanoseconds: beforeDelayWait)
        controller.enter(delay: shortDelay)  // 재시작 — 첫 enter pending 취소

        // 첫 enter 기준 delay 통과 시점 (beforeDelayWait + pastDelayWait 미만) 에 표시되면 fail
        // 두 번째 enter 기준 delay 통과까지 대기
        try await Task.sleep(nanoseconds: pastDelayWait)

        #expect(controller.isVisible == true)
    }
}
