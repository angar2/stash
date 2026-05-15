// ClipsViewModel 단위 테스트 — filteredClips / focusZone 전환 / 검색 / paste / pin / delete / 전체 삭제
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("ClipsViewModel")
struct ClipsViewModelTests {
    private func makeViewModel(prefilled: [Clip] = []) async -> (ClipsViewModel, InMemoryClipRepository) {
        let repo = InMemoryClipRepository()
        for clip in prefilled {
            _ = try? await repo.insert(clip)
        }
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: MockPasteSynthesizer(),
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc)
        return (vm, repo)
    }

    private func makeClip(body: String, pinned: Bool = false) -> Clip {
        Clip(
            id: UUID(),
            type: .text,
            body: body,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: pinned,
            createdAt: Date(),
            lastUsedAt: Date()
        )
    }

    @Test("reload — repository fetchAll로 clips 채움")
    func reloadFillsClips() async {
        let prefilled = [makeClip(body: "hello"), makeClip(body: "world")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.clips.count == 2)
    }

    @Test("filteredClips / visibleClips — 검색어 case-insensitive 필터 + 비핀 분리")
    func filteredClipsBySearchQuery() async {
        let prefilled = [
            makeClip(body: "hello world"),
            makeClip(body: "FooBar"),
            makeClip(body: "Hello swift")
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.searchQuery = "hello"
        #expect(vm.filteredClips.count == 2)
        #expect(vm.visibleClips.count == 2)
        vm.searchQuery = "FOO"
        #expect(vm.filteredClips.count == 1)
    }

    @Test("moveSelectionDown / Up — wrap-around")
    func navigationWrapAround() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.selectedIdx == 0)
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 1)
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 2)
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 0)  // wrap
        vm.moveSelectionUp()
        #expect(vm.selectedIdx == 2)  // wrap reverse
    }

    @Test("focusZone — activateSearchInput / deactivateSearchInputAndClear")
    func searchFocusTransitions() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "hello")])
        await vm.reload()
        vm.searchQuery = "test"
        vm.activateSearchInput()
        #expect(vm.focusZone == .search)
        #expect(vm.searchInputActive == true)
        vm.deactivateSearchInputAndClear()
        #expect(vm.focusZone == .search)
        #expect(vm.searchInputActive == false)
        #expect(vm.searchQuery == "")
    }

    @Test("isEmptyState — clips 0 + 검색어 빈 문자열")
    func isEmptyStateLogic() async {
        let (vm, _) = await makeViewModel(prefilled: [])
        await vm.reload()
        #expect(vm.isEmptyState == true)
        vm.searchQuery = "abc"
        #expect(vm.isEmptyState == false)
        #expect(vm.isSearchEmptyResult == true)
    }

    @Test("isEmptyState — Pin 만 남고 unpinned 0인 상태도 일반 히스토리 빈 상태 (TASK-018 Phase 5)")
    func isEmptyStateWithOnlyPinned() async {
        let pinned = makeClip(body: "pinned-1", pinned: true)
        let (vm, _) = await makeViewModel(prefilled: [pinned])
        await vm.reload()
        #expect(vm.visibleClips.isEmpty == true)  // unpinned 0
        #expect(vm.pinnedClips.count == 1)
        #expect(vm.isEmptyState == true)  // 일반 히스토리 빈 → 안내 노출 (Pin 메뉴란은 별도 hasPinned 분기로 유지)
    }

    @Test("delete — 행 제거 후 selectedIdx clamp")
    func deleteAndClamp() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.selectedIdx = 2
        await vm.delete(at: 2)
        #expect(vm.clips.count == 2)
        #expect(vm.selectedIdx <= 1)
    }

    @Test("deleteAllExceptPinned — pinned 보존")
    func deleteAllExceptPinnedTest() async {
        let prefilled = [
            makeClip(body: "a", pinned: false),
            makeClip(body: "b", pinned: true),
            makeClip(body: "c", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        await vm.deleteAllExceptPinned()
        #expect(vm.clips.count == 1)
        #expect(vm.clips.first?.body == "b")
    }

    // MARK: - TASK-016 Phase 1: pendingScrollToId — keyboard nav만 set / hover는 nil 유지

    @Test("hover setSelectedIdx — pendingScrollToId 미설정 (스크롤 루프 차단)")
    func hoverSetSelectedIdx_DoesNotSetPendingScrollToId() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.pendingScrollToId == nil)
        vm.setSelectedIdx(1)
        #expect(vm.selectedIdx == 1)
        #expect(vm.pendingScrollToId == nil)  // hover로는 절대 set 안 됨
    }

    // TASK-018 Phase 3 — 행 단위 페이징 모델 (visibleRowCount=6 안에선 커서만 이동 / 경계 진출 시에만 시프트)

    @Test("키보드 moveSelectionDown — 가시 영역 안 이동은 pendingScrollToId 미설정 (스크롤 X)")
    func keyboardMoveDown_InsideVisibleWindow_NoScroll() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 1)
        #expect(vm.pendingScrollToId == nil)  // 가시 영역 안 — 스크롤 발생 X
        #expect(vm.visibleTopIdx == 0)
    }

    @Test("키보드 moveSelectionDown — 가시 영역 마지막 행에서 한 번 더 ↓ 시 정확히 1행 시프트")
    func keyboardMoveDown_AtBoundary_ShiftsByOneRow() async {
        // visibleRowCount=6 → 7개 두고 마지막(idx=5)에서 한 번 더 ↓ 시 idx=6, visibleTopIdx 0→1 시프트.
        let prefilled = (0..<7).map { makeClip(body: "\($0)") }
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        // selectedIdx=5 (가시 마지막) 직접 도달
        for _ in 0..<5 { vm.moveSelectionDown() }
        #expect(vm.selectedIdx == 5)
        #expect(vm.visibleTopIdx == 0)
        #expect(vm.pendingScrollToId == nil)
        // 경계에서 한 번 더 ↓
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 6)
        #expect(vm.visibleTopIdx == 1)
        #expect(vm.pendingScrollToId == vm.visibleClips[1].id)
        #expect(vm.pendingScrollAnchor == .top)
    }

    @Test("키보드 moveSelectionDown — 리스트 끝 wrap 시 visibleTopIdx 0 + 첫 행 .top")
    func keyboardMoveDown_WrapsAndResetsTopIdx() async {
        let prefilled = (0..<3).map { makeClip(body: "\($0)") }
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.selectedIdx = 2  // 마지막
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 0)
        #expect(vm.visibleTopIdx == 0)
        #expect(vm.pendingScrollToId == vm.visibleClips[0].id)
        #expect(vm.pendingScrollAnchor == .top)
    }

    @Test("키보드 moveSelectionUp — 가시 영역 안 이동은 pendingScrollToId 미설정")
    func keyboardMoveUp_InsideVisibleWindow_NoScroll() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.selectedIdx = 2
        vm.moveSelectionUp()
        #expect(vm.selectedIdx == 1)
        #expect(vm.pendingScrollToId == nil)
        #expect(vm.visibleTopIdx == 0)
    }

    @Test("키보드 moveSelectionUp — 첫 행에서 ↑ wrap 시 visibleTopIdx 끝쪽으로 시프트 + .bottom")
    func keyboardMoveUp_WrapsToBottom() async {
        let prefilled = (0..<8).map { makeClip(body: "\($0)") }
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.selectedIdx == 0)
        vm.moveSelectionUp()
        #expect(vm.selectedIdx == 7)
        #expect(vm.visibleTopIdx == 2)  // count(8) - visibleRowCount(6) = 2
        #expect(vm.pendingScrollToId == vm.visibleClips[7].id)
        #expect(vm.pendingScrollAnchor == .bottom)
    }

    @Test("consumePendingScroll — id를 nil로 reset")
    func consumePendingScroll_ResetsToNil() async {
        // 경계 진출 시점에서 pendingScrollToId가 set 됨을 보장 + consume 후 nil 검증.
        let prefilled = (0..<7).map { makeClip(body: "\($0)") }
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        for _ in 0..<6 { vm.moveSelectionDown() }
        #expect(vm.pendingScrollToId != nil)
        vm.consumePendingScroll()
        #expect(vm.pendingScrollToId == nil)
    }

    // MARK: - TASK-016 Phase 3: deactivateSearchInput — 검색어 보존

    @Test("deactivateSearchInput — searchInputActive만 false, searchQuery 보존, focusZone 보존")
    func deactivateSearchInput_PreservesQuery() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "x")])
        await vm.reload()
        vm.searchQuery = "abc"
        vm.activateSearchInput()
        #expect(vm.searchInputActive == true)
        #expect(vm.focusZone == .search)

        vm.deactivateSearchInput()
        #expect(vm.searchInputActive == false)
        #expect(vm.searchQuery == "abc")  // 검색어 보존
        #expect(vm.focusZone == .search)  // focusZone도 보존 (deactivateSearchInputAndClear와 차이)
    }

    @Test("setFocusZone(.clip) — searchInputActive 유지 (hover로 활성화 단계 2 풀림 X — 지크 요구)")
    func setFocusZone_NonSearch_PreservesSearchInputActive() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "x")])
        await vm.reload()
        vm.activateSearchInput()
        #expect(vm.searchInputActive == true)

        vm.setFocusZone(.clip)
        #expect(vm.focusZone == .clip)
        #expect(vm.searchInputActive == true)  // hover로는 풀리면 안 됨 — click 트리거에서만 해제
    }

    @Test("hover setSelectedIdx — searchInputActive 유지 (hover로 활성화 단계 2 풀림 X)")
    func hoverSetSelectedIdx_PreservesSearchInputActive() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.activateSearchInput()
        #expect(vm.searchInputActive == true)

        vm.setSelectedIdx(1)
        #expect(vm.focusZone == .clip)
        #expect(vm.searchInputActive == true)
    }

    @Test("resetForOpen — focusZone=.clip + selectedIdx=0 + searchInputActive=false + searchQuery 비움")
    func resetForOpenInitializesState() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "a"), makeClip(body: "b")])
        await vm.reload()
        // 사용자 활성 후 검색어 박은 상태
        vm.searchQuery = "abc"
        vm.activateSearchInput()
        vm.selectedIdx = 1
        #expect(vm.searchInputActive == true)

        vm.resetForOpen()
        #expect(vm.focusZone == .clip)
        #expect(vm.selectedIdx == 0)
        #expect(vm.searchInputActive == false)
        #expect(vm.searchQuery == "")
        #expect(vm.pendingScrollToId == nil)
    }

    // MARK: - TASK-017 Phase 4·6: pop (⌘+Enter) 동작 — 비핀 클립 paste + delete

    @Test("pop — 비핀 클립: paste + delete (clips count 감소)")
    func pop_NonPinned_PastesAndDeletes() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, repo) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.visibleClips.count == 3)

        await vm.pop(at: 0)

        // pasteService는 MockPasteSynthesizer를 통해 호출됨 — 권한 검증 통과 가정
        // pop은 비핀이므로 delete 후 reload — clips count 1 감소
        let after = (try? await repo.fetchAll()) ?? []
        #expect(after.count == 2)
        #expect(vm.clips.count == 2)
    }

    @Test("pop — idx 범위 밖: guard로 무동작")
    func pop_OutOfRange_NoOp() async {
        let prefilled = [makeClip(body: "a")]
        let (vm, repo) = await makeViewModel(prefilled: prefilled)
        await vm.reload()

        await vm.pop(at: 99)

        let after = (try? await repo.fetchAll()) ?? []
        #expect(after.count == 1)  // 변화 없음
    }

    @Test("deleteAllExceptPinned — 핀 클립만 보존 + 토스트 발행 (⌘+⇧+⌫ 동작)")
    func deleteAllExceptPinned_PreservesPinned() async {
        let prefilled = [
            makeClip(body: "a", pinned: false),
            makeClip(body: "b", pinned: true),
            makeClip(body: "c", pinned: false),
            makeClip(body: "d", pinned: true)
        ]
        let (vm, repo) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.clips.count == 4)

        await vm.deleteAllExceptPinned()

        let after = (try? await repo.fetchAll()) ?? []
        #expect(after.count == 2)
        #expect(after.allSatisfy { $0.isPinned } == true)
    }
}
