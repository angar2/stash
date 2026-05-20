// ClipsViewModel.effectiveClipListHeight 단위 테스트 — TASK-037 디스플레이 환경설정 동적 frame 매트릭스 (autoFit ON/OFF × N × visibleCount + floor=3 룰).
import Testing
import Foundation
import AppKit
@testable import stash

@MainActor
@Suite("ClipListHeight", .serialized)
struct ClipListHeightTests {

    private let rowHeight: CGFloat = DesignTokens.Spacing.rowMinHeight
    private let rowGap: CGFloat = DesignTokens.Spacing.rowGap

    /// 행 수 → 컨테이너 raw 높이.
    private func raw(_ rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowGap
    }

    /// 테스트 시작 시 UserDefaults 격리 + 사후 default 복원.
    private func withDefaults(n: Int, autoFit: Bool, _ body: () -> Void) {
        let prevN = UserDefaults.standard.integer(forKey: "clipsPerPage")
        let prevAutoFit = UserDefaults.standard.bool(forKey: "autoFitClipListHeight")
        UserDefaults.standard.set(n, forKey: "clipsPerPage")
        UserDefaults.standard.set(autoFit, forKey: "autoFitClipListHeight")
        body()
        UserDefaults.standard.set(prevN, forKey: "clipsPerPage")
        UserDefaults.standard.set(prevAutoFit, forKey: "autoFitClipListHeight")
    }

    @Test("autoFit OFF + N=10 + visible=3 → N×rowHeight 고정")
    func autoFitOff_returnsNRows() {
        withDefaults(n: 10, autoFit: false) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 3, hasPinned: false)
            // 화면 cap 영향 가능 — 실제 모니터 가용 높이 작을 때 min 적용. 본 단위 테스트는 raw 값 vs h min 비교로 안전.
            #expect(h <= raw(10))
            #expect(h > 0)
        }
    }

    @Test("autoFit ON + N=10 + visible=5 → visible 만큼 수축 (5행)")
    func autoFitOn_shrinksToVisibleCount() {
        withDefaults(n: 10, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 5, hasPinned: false)
            #expect(h == raw(5))
        }
    }

    @Test("autoFit ON + N=10 + visible=20 → N 만큼 cap (10행)")
    func autoFitOn_capsAtN() {
        withDefaults(n: 10, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 20, hasPinned: false)
            #expect(h == raw(10))
        }
    }

    @Test("autoFit ON + N=20 + visible=1 → floor=3 강제 (3행)")
    func autoFitOn_floorAtThree_visibleOne() {
        withDefaults(n: 20, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 1, hasPinned: false)
            #expect(h == raw(3))
        }
    }

    @Test("autoFit ON + N=20 + visible=2 → floor=3 강제 (3행)")
    func autoFitOn_floorAtThree_visibleTwo() {
        withDefaults(n: 20, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 2, hasPinned: false)
            #expect(h == raw(3))
        }
    }

    @Test("autoFit ON + N=1 + visible=5 → N 우선 (1행, floor=N)")
    func autoFitOn_floorRespectsN_NOne() {
        withDefaults(n: 1, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 5, hasPinned: false)
            #expect(h == raw(1))
        }
    }

    @Test("autoFit ON + N=2 + visible=5 → N 우선 (2행, floor=N)")
    func autoFitOn_floorRespectsN_NTwo() {
        withDefaults(n: 2, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 5, hasPinned: false)
            #expect(h == raw(2))
        }
    }

    @Test("autoFit ON + N=2 + visible=1 → floor=min(N,3)=2 보장 (2행, N 우선이 더 강함)")
    func autoFitOn_NTwo_visibleOne_floorHonored() {
        withDefaults(n: 2, autoFit: true) {
            // max(min(1, 2), min(2, 3)) = max(1, 2) = 2 → 2행. N=2 사용자에게 *최소 2행* 보장.
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 1, hasPinned: false)
            #expect(h == raw(2))
        }
    }

    @Test("autoFit ON + N=6 + visible=0 → floor=3 강제 (visible=0 도 본 헬퍼 호출 시 floor 적용)")
    func autoFitOn_visibleZero_appliesFloor() {
        // 실제 동작: visibleCount=0 인 경우 HistoryPopover.emptyState 가 표시되므로 본 헬퍼 호출 대상 X.
        // 단 헬퍼 단독 호출 시 floor 룰 적용 일관성 검증.
        withDefaults(n: 6, autoFit: true) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 0, hasPinned: false)
            #expect(h == raw(3))  // max(min(0, 6), min(6, 3)) = max(0, 3) = 3
        }
    }

    @Test("autoFit OFF + N=1 + visible=10 → 1행 고정")
    func autoFitOff_NOne_returnsOneRow() {
        withDefaults(n: 1, autoFit: false) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 10, hasPinned: false)
            #expect(h == raw(1))
        }
    }

    @Test("UserDefaults 잘못된 값 (0 또는 음수) — clamp 1")
    func clampsToOne_whenUserDefaultsZeroOrNegative() {
        withDefaults(n: 0, autoFit: false) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 5, hasPinned: false)
            #expect(h == raw(1))
        }
    }

    @Test("UserDefaults 50 초과 — clamp 50")
    func clampsToMax_whenUserDefaultsOverMax() {
        withDefaults(n: 500, autoFit: false) {
            let h = ClipsViewModel.effectiveClipListHeightFromUserDefaults(visibleCount: 5, hasPinned: false)
            // raw(50) 또는 화면 cap. 본 단위 테스트는 raw(50) 이하 보장 검증.
            #expect(h <= raw(50))
        }
    }
}
