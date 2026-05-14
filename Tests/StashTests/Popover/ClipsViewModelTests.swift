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
}
