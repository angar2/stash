// TASK-057 — `ClipsViewModel.resolveNewClipsPerPageForResize` + `cappedRowsForCurrentScreen` 단위 테스트.
// `PopoverWindow.windowWillResize` 의 raw vs effective 동기화 분기 결정 로직 회귀 가드.
import Testing
import Foundation
import AppKit
@testable import stash

@MainActor
@Suite("ClipsViewModelResizeSync", .serialized)
struct ClipsViewModelResizeSyncTests {

    // MARK: - resolveNewClipsPerPageForResize — 분기 케이스 8종

    @Test("Case A: raw>cap 축소 (raw=50, signDelta=-1, cap=27 → 26)")
    func caseA_rawOverCap_shrinkOne() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 50, signDelta: -1, capRows: 27)
        #expect(result == 26)
    }

    @Test("Case B: raw>cap 축소 다단 step (raw=50, signDelta=-3, cap=27 → 24)")
    func caseB_rawOverCap_shrinkMultiStep() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 50, signDelta: -3, capRows: 27)
        #expect(result == 24)
    }

    @Test("Case C: raw>cap 축소 + min clamp (raw=50, signDelta=-30, cap=10 → clipsPerPageMin)")
    func caseC_rawOverCap_minClamp() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 50, signDelta: -30, capRows: 10)
        #expect(result == Constants.clipsPerPageMin)
    }

    @Test("Case D: cap 미달 축소 (raw=20, signDelta=-1, cap=27 → 19)")
    func caseD_underCap_shrink() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 20, signDelta: -1, capRows: 27)
        #expect(result == 19)
    }

    @Test("Case E: cap 미달 늘림 (raw=20, signDelta=+1, cap=27 → 21)")
    func caseE_underCap_grow() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 20, signDelta: +1, capRows: 27)
        #expect(result == 21)
    }

    @Test("Case F: raw>cap 늘림 시도 + max clamp (raw=50, signDelta=+1, cap=27 → 50)")
    func caseF_rawOverCap_growClamp() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 50, signDelta: +1, capRows: 27)
        #expect(result == Constants.clipsPerPageMax)
    }

    @Test("Case G: cap 미달 늘림 + max clamp (raw=49, signDelta=+5, cap=60 → 50)")
    func caseG_underCap_growMaxClamp() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 49, signDelta: +5, capRows: 60)
        #expect(result == Constants.clipsPerPageMax)
    }

    @Test("Case H: raw==cap 경계 축소 (raw=27, signDelta=-1, cap=27 → 26, else 분기)")
    func caseH_rawEqualsCap_shrink() {
        let result = ClipsViewModel.resolveNewClipsPerPageForResize(current: 27, signDelta: -1, capRows: 27)
        #expect(result == 26)
    }

    // MARK: - cappedRowsForCurrentScreen — smoke 검증

    @Test("cappedRowsForCurrentScreen 결과 ≥ 1 (최소값 보장)")
    func cappedRows_minimumOne() {
        let result = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true)
        #expect(result >= 1)
    }

    @Test("hasPinned=true → hasPinned=false 보다 작거나 같음 (pinRow overhead 차감)")
    func cappedRows_pinnedReduces() {
        let withoutPinned = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true)
        let withPinned = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: true, hintBarVisible: true)
        #expect(withPinned <= withoutPinned)
    }

    @Test("hintBarVisible=false → hintBarVisible=true 보다 크거나 같음 (hintBar overhead 차감)")
    func cappedRows_hintBarHiddenExpands() {
        let visible = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: true)
        let hidden = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: false, hintBarVisible: false)
        #expect(hidden >= visible)
    }
}
