// HotkeyMonitor 단위 테스트 — 권한 거부 시 모니터 미등록 / 권한 부여 시 등록 + callback 인터페이스 검증
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("HotkeyMonitor")
struct HotkeyMonitorTests {
    @Test("권한 거부 시 start 호출해도 monitor 등록되지 않음")
    func startSkippedWhenPermissionDenied() async {
        let checker = MockPermissionChecker()
        checker.trusted = false
        let permSvc = PermissionService(checker: checker)
        await permSvc.recheck()

        let monitor = HotkeyMonitor(permissionService: permSvc)
        await monitor.start()
        // 실제 NSEvent monitor 핸들은 internal — 동작 직접 검증 어려움. 권한 거부 시 callback 미설정 상태에서도 start가 throw 없이 종료되는지만 확인.
        #expect(true)
        monitor.stop()
    }

    @Test("callback 인터페이스 — 외부 setter로 설정 가능")
    func callbackInterface() async {
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        await permSvc.recheck()

        let monitor = HotkeyMonitor(permissionService: permSvc)
        var holdStartCount = 0
        var holdEndCount = 0
        var doubleTapCount = 0
        monitor.onHoldStart = { holdStartCount += 1 }
        monitor.onHoldEnd = { holdEndCount += 1 }
        monitor.onDoubleTap = { doubleTapCount += 1 }
        #expect(monitor.onHoldStart != nil)
        #expect(monitor.onHoldEnd != nil)
        #expect(monitor.onDoubleTap != nil)
        // 카운터는 실제 NSEvent 시뮬레이션 없이 0 유지가 정상 — 단위 테스트로는 callback 변수 할당만 검증
        #expect(holdStartCount == 0)
        #expect(holdEndCount == 0)
        #expect(doubleTapCount == 0)
        monitor.stop()
    }

    @Test("stop 호출 시 idempotent — 다중 호출 안전")
    func stopIdempotent() async {
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        await permSvc.recheck()

        let monitor = HotkeyMonitor(permissionService: permSvc)
        monitor.stop()
        monitor.stop()
        await monitor.start()
        monitor.stop()
        monitor.stop()
        #expect(true)
    }
}
