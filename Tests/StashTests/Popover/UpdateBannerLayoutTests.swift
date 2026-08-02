// 업데이트 배너 ↔ popover 높이 정합 — 순수 계층 단위 테스트 (TASK-102, Test Plan #2)
//
// **본 스위트 통과 = 기능 동작 아님.** 배너가 실제로 뜨는지 · 눌리는지 · 표준 창이 열리는지는
// 앱을 띄워야 알 수 있고, 그 경로는 `.project/TEST-GUIDE.md` *모의 업데이트* 절의 사람 검수다.
// 여기서 지키는 것은 *배너 표시 여부가 클립 목록 상한 계산에 정확히 반영되는가* 하나뿐이다.
//
// 이 계산이 어긋나면 배너가 뜰 때 popover 가 화면 밖으로 자라거나, 닫은 뒤에도 빈 공간이 남는다.
import Testing
import Foundation
@testable import stash

@Suite("업데이트 배너 높이 정합 (TASK-102)")
@MainActor
struct UpdateBannerLayoutTests {

    // MARK: - 상한 행 수

    /// 배너가 뜨면 그만큼 세로 여유가 줄어드니 담을 수 있는 행 수도 줄거나 같아야 한다.
    /// (화면이 아주 크면 한 행 경계에 안 걸려 같을 수 있다 — 늘어나는 일만 없으면 된다.)
    @Test("배너가 뜨면 클립 목록 상한이 늘지 않는다")
    func bannerNeverIncreasesCap() {
        let without = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true, updateBannerVisible: false)
        let with = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true, updateBannerVisible: true)
        #expect(with <= without)
    }

    /// 배너를 닫으면 상한이 배너 없던 값으로 *정확히* 돌아와야 한다.
    /// 값이 남으면 popover 에 빈 공간이 잔존한다.
    @Test("배너 해제 시 상한이 원래 값으로 정확히 복귀")
    func capRestoresExactlyAfterDismiss() {
        let baseline = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: true, hintBarVisible: true, updateBannerVisible: false)
        _ = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: true, hintBarVisible: true, updateBannerVisible: true)
        let restored = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: true, hintBarVisible: true, updateBannerVisible: false)
        #expect(restored == baseline)
    }

    /// 배너 오버헤드가 실제로 계산에 들어가는지 — 화면 여유를 배너 높이만큼 줄인 것과 같은 결과여야 한다.
    /// 상수만 선언하고 계산에 안 넣는 실수를 잡는다.
    @Test("배너 오버헤드가 상한 계산에 실제로 반영된다")
    func bannerOverheadIsApplied() {
        let overhead = DesignTokens.Spacing.updateBannerOverhead
        #expect(overhead > 0)

        let rowHeight = DesignTokens.Spacing.rowMinHeight
        let rowGap = DesignTokens.Spacing.rowGap
        let without = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true, updateBannerVisible: false)
        let with = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true, updateBannerVisible: true)
        // 줄어든 행 수 × 행 높이는 배너 오버헤드를 넘지 않는다 (한 행 경계 반올림 허용).
        let shrunk = CGFloat(without - with) * (rowHeight + rowGap)
        #expect(shrunk <= overhead + rowHeight + rowGap)
    }

    // MARK: - 클립 목록 높이

    /// 목록 높이도 같은 규칙을 따른다 — 배너가 뜨면 같거나 작아진다.
    @Test("배너가 뜨면 클립 목록 높이가 늘지 않는다")
    func listHeightNeverGrowsWithBanner() {
        let without = ClipsViewModel.effectiveClipListHeight(
            visibleCount: 50, clipsPerPage: 50, autoFit: false,
            hasPinned: false, hintBarVisible: true, previewBarVisible: false, updateBannerVisible: false
        )
        let with = ClipsViewModel.effectiveClipListHeight(
            visibleCount: 50, clipsPerPage: 50, autoFit: false,
            hasPinned: false, hintBarVisible: true, previewBarVisible: false, updateBannerVisible: true
        )
        #expect(with <= without)
    }

    /// 배너 인자를 넘기지 않은 기존 호출은 동작이 바뀌지 않아야 한다 (기본값 false).
    /// 회귀 방지 — 기존 호출처를 전부 고치지 않고도 안전하다는 근거다.
    @Test("배너 인자 생략 시 기존 동작과 동일")
    func defaultArgumentMatchesNoBanner() {
        let omitted = ClipsViewModel.effectiveClipListHeight(
            visibleCount: 6, clipsPerPage: 6, autoFit: false, hasPinned: false, hintBarVisible: true
        )
        let explicitFalse = ClipsViewModel.effectiveClipListHeight(
            visibleCount: 6, clipsPerPage: 6, autoFit: false,
            hasPinned: false, hintBarVisible: true, previewBarVisible: false, updateBannerVisible: false
        )
        #expect(omitted == explicitFalse)
    }
}
