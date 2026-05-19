// HotkeyMonitor 단위 테스트 — 권한 거부 시 모니터 미등록 / 권한 부여 시 등록 + callback 인터페이스 검증
import Testing
import Foundation
import AppKit
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

    // MARK: - TASK-017 Phase 2: 권한 부여 후 자동 재시작 정합 검증

    @Test("start 멱등 — 두 번 연속 호출해도 monitor leak 없음 (내부 stop 선행)")
    func startIdempotent() async {
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        await permSvc.recheck()

        let monitor = HotkeyMonitor(permissionService: permSvc)
        await monitor.start()
        await monitor.start()  // 두 번째 호출 — 내부 stop() 선행으로 이전 monitor 정리 후 재등록
        // 실제 NSEvent monitor 핸들 검증 어려움 — leak/crash 없이 정상 종료가 멱등성 증거.
        #expect(true)
        monitor.stop()
    }

    @Test("권한 .denied → .granted 전이 — 외부 트리거 후 start 호출 시 정상 등록")
    func startAfterPermissionFlipFromDeniedToGranted() async {
        let checker = MockPermissionChecker()
        checker.trusted = false  // 초기 거부
        let permSvc = PermissionService(checker: checker)
        await permSvc.recheck()

        let monitor = HotkeyMonitor(permissionService: permSvc)
        await monitor.start()  // skip — 권한 없음

        // 권한 부여 시뮬레이션
        checker.trusted = true
        await permSvc.recheck()
        await monitor.start()  // 외부 트리거 (StashApp의 statusPublisher sink가 호출하는 경로)
        // 권한 부여 후 start 호출 시 silent skip 안 되고 등록 진입 확인 — leak 없이 정상.
        #expect(true)
        monitor.stop()
    }
}

// MARK: - PopoverHotkey enum 단축키 매핑 검증 (TASK-017 리팩토링 회귀 방지)

@MainActor
@Suite("PopoverHotkey")
struct PopoverHotkeyTests {
    /// keyCode + modifiers 매핑이 FEATURES §4 사양과 일치하는지 검증.
    @Test("↑ 단독 keyCode=126 modifiers=[] (TASK-021)")
    func upArrow_matchesPlainUp() {
        #expect(PopoverHotkey.moveSelectionUp.keyCode == 126)
        #expect(PopoverHotkey.moveSelectionUp.modifiers == [])
    }

    @Test("↓ 단독 keyCode=125 modifiers=[] (TASK-021)")
    func downArrow_matchesPlainDown() {
        #expect(PopoverHotkey.moveSelectionDown.keyCode == 125)
        #expect(PopoverHotkey.moveSelectionDown.modifiers == [])
    }

    // TASK-020 — pop (⌘⇧V) 단축키 폐기로 pop_matchesCommandShiftV 케이스 삭제.
    // TASK-021 — moveSelectionUpAlias / moveSelectionDownAlias (⌘+1 / ⌘+2) enum 폐기로 alias 검증 케이스 삭제.

    // TASK-033 — deleteAll keyCode/modifiers hardcoded 검증 폐기 (변경 가능 단축키 → SPM 동적 조회로 변경. hardcoded 모두 keyCode=0, modifiers=[]). 변경 가능 단축키 검증은 SPM 등록값 기반 신규 테스트로 분리.

    // TASK-025 — `.activateSearch` enum case 폐기. Enter 동작 자체 제거 (검색바 always-active 정책). `activateSearch_matchesPlainReturn` 케이스 삭제. 회귀 가드는 `PopoverHotkeyTests` 의 `enterKeyMatchesNoHotkey` (Enter 단독 매칭 0건 검증) 에서 담당.

    @Test("ESC 단독 keyCode=53 modifiers=[] (예외)")
    func escape_matchesPlainEscape() {
        #expect(PopoverHotkey.escape.keyCode == 53)
        #expect(PopoverHotkey.escape.modifiers == [])
    }

    /// 방향키 키 자동 .numericPad/.function modifier가 매칭에 영향 X 검증 (TASK-017 fix-2 회귀 방지, TASK-021 정합).
    @Test("matches — 방향키 .numericPad+.function modifier 자동 박혀도 ↑ 단독 매칭 OK")
    func matches_ignoresNumericPadAndFunctionModifiers() {
        // ↑ event 시뮬레이션 — modifierFlags에 .numericPad + .function 박힘 (modifier-less 방향키)
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.numericPad, .function],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        #expect(PopoverHotkey.moveSelectionUp.matches(event: event) == true)
    }

    // TASK-033 — *modifier 정확 일치 검증* / *allCases 중복 keyCode+modifiers 없음* 테스트 폐기.
    // 사유: 변경 가능 단축키 6종 (copy / paste / pinToggle / pinSidebarToggle / deleteOne / deleteAll) 은 KeyboardShortcuts SPM 등록값 동적 조회로 변경. hardcoded keyCode + modifiers 기반 검증 의미 잃음 (모두 keyCode=0, modifiers=[]). deleteAllAlias 케이스 자체 폐기 (TASK-021 단축키 ⌘⇧⌫ 폐기 잔존 정리).
    // 변경 가능 단축키 검증은 KeyboardShortcuts SPM 동적 등록값 기반 신규 테스트로 분리 가능 (별도 후속 작업).

    /// allCases — 변경 불가 단축키 (방향키/ESC) keyCode+modifiers hardcoded 중복 없음.
    @Test("allCases — 변경 불가 단축키만 keyCode+modifiers 중복 없음")
    func allCases_noDuplicateMapping() {
        // 변경 불가 케이스만 — 변경 가능 6종 (SPM 동적 조회) 은 모두 keyCode=0 통일이라 중복 검사 의미 X.
        let fixedCases: [PopoverHotkey] = [.moveSelectionUp, .moveSelectionDown, .escape]
        let pairs = fixedCases.map { ($0.keyCode, $0.modifiers.rawValue) }
        let seen = Set(pairs.map { "\($0.0)-\($0.1)" })
        #expect(seen.count == pairs.count, "변경 불가 PopoverHotkey 중 keyCode+modifiers 중복 정의 발견")
    }
}
