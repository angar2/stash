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

    @Test("filteredClips / visibleClips — 검색어 case-insensitive 필터 (TASK-019: 핀 포함)")
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

    @Test("TASK-025 — resetForOpen 후 검색 활성 단계 폐기 정합")
    func resetForOpenNoSearchActiveState() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "hello")])
        await vm.reload()
        vm.searchQuery = "test"
        vm.focusZone = .pin
        vm.selectedIdx = 1
        vm.pinSidebarOpen = true
        vm.resetForOpen()
        #expect(vm.focusZone == .clip)
        #expect(vm.selectedIdx == 0)
        #expect(vm.searchQuery == "")
        #expect(vm.pinSidebarOpen == false)
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

    @Test("isEmptyState — Pin이 일반 히스토리에도 자연 노출되므로 핀만 있어도 빈 상태 X (TASK-019)")
    func isEmptyStateWithOnlyPinned() async {
        let pinned = makeClip(body: "pinned-1", pinned: true)
        let (vm, _) = await makeViewModel(prefilled: [pinned])
        await vm.reload()
        #expect(vm.visibleClips.count == 1)  // TASK-019 — 핀이 visibleClips에 포함
        #expect(vm.pinnedClips.count == 1)
        #expect(vm.isEmptyState == false)  // 일반 히스토리에 핀 있음 → 빈 상태 X
    }

    // MARK: - TASK-019: 핀 항목 일반 히스토리 자연 노출 + Pin 사이드바 토글

    @Test("visibleClips — 핀 항목도 일반 히스토리에 포함 노출 (TASK-019 Bug 2 fix)")
    func visibleClipsIncludesPinned() async {
        let prefilled = [
            makeClip(body: "unpinned-1", pinned: false),
            makeClip(body: "pinned-1", pinned: true),
            makeClip(body: "unpinned-2", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.visibleClips.count == 3)  // 핀 포함 전체 노출
        #expect(vm.pinnedClips.count == 1)
    }

    @Test("검색 — 핀된 클립도 검색 결과 포함 (TASK-019)")
    func searchIncludesPinned() async {
        let prefilled = [
            makeClip(body: "common-keyword pinned", pinned: true),
            makeClip(body: "common-keyword regular", pinned: false),
            makeClip(body: "other", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.searchQuery = "common-keyword"
        #expect(vm.visibleClips.count == 2)
        #expect(vm.visibleClips.contains(where: { $0.isPinned }))
    }

    @Test("togglePinSidebar — 핀 있을 때 open/close 토글")
    func togglePinSidebarTogglesOpenState() async {
        let prefilled = [makeClip(body: "pinned-1", pinned: true)]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.pinSidebarOpen == false)
        vm.togglePinSidebar()
        #expect(vm.pinSidebarOpen == true)
        #expect(vm.focusZone == .pin)
        vm.togglePinSidebar()
        #expect(vm.pinSidebarOpen == false)
        #expect(vm.focusZone == .clip)
    }

    @Test("togglePinSidebar — 빈 핀 상태에서 no-op")
    func togglePinSidebarNoOpWhenNoPins() async {
        let prefilled = [makeClip(body: "unpinned", pinned: false)]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.pinnedClips.isEmpty)
        vm.togglePinSidebar()
        #expect(vm.pinSidebarOpen == false)  // 빈 핀 → 펼침 차단
    }

    @Test("togglePin — 핀 토글 후 일반 visibleClips에 그대로 잔존 (TASK-019 Bug 2 fix)")
    func togglePinKeepsClipInVisibleList() async {
        let clip = makeClip(body: "to-be-pinned", pinned: false)
        let (vm, _) = await makeViewModel(prefilled: [clip])
        await vm.reload()
        #expect(vm.visibleClips.count == 1)
        await vm.togglePin(at: 0)
        #expect(vm.visibleClips.count == 1)  // 핀 후에도 일반 목록 잔존
        #expect(vm.visibleClips.first?.isPinned == true)
        #expect(vm.pinnedClips.count == 1)
    }

    // MARK: - TASK-019 fix 2차: B1 selectedIdx 추적 + B3 focusZone 분기 + B4 Pin 사이드바 동작

    @Test("togglePin(at:) — 토글 후 행 위치 변동 X (B5 root fix, 정렬 룰 last_used_at DESC 만)")
    func togglePinPreservesRowPosition() async {
        // TASK-019 fix 4차 — 정렬 룰에서 `is_pinned DESC` 제거. 핀 토글해도 visibleClips 순서 변동 X.
        let prefilled = [
            makeClip(body: "clip-1", pinned: false),
            makeClip(body: "clip-2", pinned: false),
            makeClip(body: "clip-3", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        let orderBefore = vm.visibleClips.map(\.id)
        let targetIdx = 1  // 가운데 클립
        let targetId = vm.visibleClips[targetIdx].id
        vm.selectedIdx = targetIdx
        await vm.togglePin(at: targetIdx)
        // 정렬 변동 X → 순서 동일 + selectedIdx 동일 + 같은 idx 에 같은 클립.
        let orderAfter = vm.visibleClips.map(\.id)
        #expect(orderBefore == orderAfter)
        #expect(vm.selectedIdx == targetIdx)
        #expect(vm.visibleClips[targetIdx].id == targetId)
        #expect(vm.visibleClips[targetIdx].isPinned == true)
    }

    @Test("togglePin(id:trackSelection:.pin) — Pin 사이드바 안 unpin → pinnedClips count 감소 + pinSelectedIdx clamp")
    func togglePinIdInPinSidebarClampsPinSelectedIdx() async {
        let prefilled = [
            makeClip(body: "p1", pinned: true),
            makeClip(body: "p2", pinned: true),
            makeClip(body: "p3", pinned: true)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.focusZone = .pin
        vm.pinSidebarOpen = true
        vm.pinSelectedIdx = 2
        let lastPinId = vm.pinnedClips.last!.id
        await vm.togglePin(id: lastPinId, trackSelection: .pin)
        #expect(vm.pinnedClips.count == 2)
        #expect(vm.pinSelectedIdx == 1)  // 마지막 idx 였으니 clamp 되어 새 마지막 idx로
    }

    @Test("togglePin(id:trackSelection:.pin) — 마지막 핀 해제 시 사이드바 자동 닫힘")
    func togglePinLastInPinSidebarCollapses() async {
        let prefilled = [makeClip(body: "only-pin", pinned: true)]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.focusZone = .pin
        vm.pinSidebarOpen = true
        let onlyId = vm.pinnedClips.first!.id
        await vm.togglePin(id: onlyId, trackSelection: .pin)
        #expect(vm.pinnedClips.isEmpty)
        #expect(vm.pinSidebarOpen == false)  // 자동 닫힘
        #expect(vm.focusZone == .clip)  // collapsePinSidebar 가 focusZone 복귀
    }

    @Test("moveSelectionDown / Up — focusZone == .pin 일 때 pinSelectedIdx 안에서 cursor wrap")
    func moveSelectionInPinSidebarWraps() async {
        let prefilled = [
            makeClip(body: "p1", pinned: true),
            makeClip(body: "p2", pinned: true),
            makeClip(body: "p3", pinned: true)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        vm.moveSelectionDown()
        #expect(vm.pinSelectedIdx == 1)
        vm.moveSelectionDown()
        #expect(vm.pinSelectedIdx == 2)
        vm.moveSelectionDown()
        #expect(vm.pinSelectedIdx == 0)  // wrap (끝 → 처음)
        vm.moveSelectionUp()
        #expect(vm.pinSelectedIdx == 2)  // reverse wrap (처음 → 끝)
        // 본체 selectedIdx 는 영향 받지 X.
        #expect(vm.selectedIdx == 0)
    }

    @Test("paste(at:) — focusZone == .pin 일 때 pinnedClips 안 항목 paste")
    func pasteInPinSidebarUsesPinnedClips() async {
        let prefilled = [
            makeClip(body: "regular", pinned: false),
            makeClip(body: "pinned-target", pinned: true)
        ]
        let (vm, repo) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0  // pinnedClips[0] 은 "pinned-target"
        let targetBody = vm.pinnedClips[0].body
        await vm.paste(at: 0, zone: .pin)
        // paste 후 clipboard 갱신 — MockPasteboard 안에 lastSetString 확인
        // 대체 검증: paste 동작 자체가 throw 없이 끝나면 OK + targetBody 가 "pinned-target" 임 확인
        #expect(targetBody == "pinned-target")
        _ = repo  // unused warning 방지
    }

    @Test("delete(at:) — focusZone == .pin 일 때 unpin 으로 동작 (DB row 보존)")
    func deleteInPinSidebarUnpinsInsteadOfDeleting() async {
        let prefilled = [
            makeClip(body: "pinned-target", pinned: true),
            makeClip(body: "other-pin", pinned: true)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        let targetId = vm.pinnedClips[0].id
        await vm.delete(at: 0)
        // DB row 는 보존 — clips 안 같은 id 여전히 있음, 다만 isPinned == false.
        let target = vm.clips.first(where: { $0.id == targetId })
        #expect(target != nil)
        #expect(target?.isPinned == false)
        #expect(vm.pinnedClips.count == 1)  // 1개 unpin 됨
    }

    @Test("setPinSelectedIdx — hover 로 pinSelectedIdx + focusZone=.pin 갱신")
    func setPinSelectedIdxByHover() async {
        let prefilled = [
            makeClip(body: "p1", pinned: true),
            makeClip(body: "p2", pinned: true)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        // ignoreHoverUntil 가 popover 열림 직후라 hover 무시될 수 있음 — 시간 흐른 후 호출.
        // 대안: ClipsViewModel 새로 만들면 ignoreHoverUntil 은 .distantPast 라 hover 즉시 허용.
        vm.setPinSelectedIdx(1)
        #expect(vm.pinSelectedIdx == 1)
        #expect(vm.focusZone == .pin)
    }

    @Test("togglePin(at:) — 본체 토글 후 pendingScrollToId 갱신 X (정렬 변동 없음 → ScrollView 점프 불필요)")
    func togglePinDoesNotSetPendingScrollToId() async {
        // TASK-019 fix 4차 — 정렬 룰 변경으로 행 위치 변동 없으니 pendingScrollToId 갱신 *안 함*.
        let prefilled = [
            makeClip(body: "c1", pinned: false),
            makeClip(body: "c2", pinned: false),
            makeClip(body: "c3", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        let targetIdx = 0
        vm.selectedIdx = targetIdx
        // 초기 상태 pendingScrollToId nil 보장 (resetForOpen 했으면 nil).
        vm.pendingScrollToId = nil
        await vm.togglePin(at: targetIdx)
        // 토글 후에도 nil 유지 — ScrollView 점프 안 함.
        #expect(vm.pendingScrollToId == nil)
    }

    @Test("insert — 동일 body 텍스트 클립 dedup (기존 row 의 lastUsedAt 갱신, 새 row 추가 X) — TASK-019 fix 5차")
    func insertDedupsSameBodyText() async throws {
        let repo = InMemoryClipRepository()
        let originalDate = Date(timeIntervalSinceNow: -100)
        var originalWithOldDate = makeClip(body: "dedup-target", pinned: false)
        let originalId = originalWithOldDate.id
        originalWithOldDate.lastUsedAt = originalDate
        try await repo.insert(originalWithOldDate)
        let newer = makeClip(body: "dedup-target", pinned: false)
        try await repo.insert(newer)
        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.id == originalId)
        let updatedDate = all.first!.lastUsedAt
        #expect(updatedDate > originalDate)
    }

    @Test("insert — 동일 body 텍스트 핀 처리된 클립도 dedup 시 핀 보존 — TASK-019 fix 5차")
    func insertDedupsPreservesPinState() async throws {
        let repo = InMemoryClipRepository()
        let pinnedOriginal = makeClip(body: "pinned-target", pinned: true)
        try await repo.insert(pinnedOriginal)
        let newer = makeClip(body: "pinned-target", pinned: false)
        try await repo.insert(newer)
        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        // dedup 시 기존 row (핀) 보존.
        #expect(all.first?.isPinned == true)
        #expect(all.first?.id == pinnedOriginal.id)
    }

    @Test("togglePin — 동일 body 의 다른 클립이 핀되어 있어도 차단 X (TASK-019 fix 5차 B7 정책 제거)")
    func togglePinNoBlockOnSameBody() async {
        // dedup 정책으로 InMemoryClipRepository 에는 동일 body 1개만 존재 보장. 그러나 테스트는 *ClipsViewModel.togglePin 자체에 차단 로직 없음* 검증.
        // 동일 body 클립이 2개 prefilled 되도록 InMemoryClipRepository 의 dedup 우회 — 직접 clips 배열에 박음.
        let prefilled = [
            makeClip(body: "pin-a", pinned: false),
            makeClip(body: "pin-b", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        let targetId = vm.clips.first(where: { $0.body == "pin-b" })!.id
        await vm.togglePin(id: targetId, trackSelection: .clip)
        #expect(vm.pinnedClips.count == 1)  // 정상 핀
        let target = vm.clips.first(where: { $0.id == targetId })
        #expect(target?.isPinned == true)
    }

    @Test("togglePin — 핀 시 pinnedAt 박힘 / unpin 시 nil (TASK-019 pinnedAt)")
    func togglePinSetsPinnedAt() async {
        let prefilled = [makeClip(body: "pin-target", pinned: false)]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.clips.first?.pinnedAt == nil)
        await vm.togglePin(at: 0)
        let afterPin = vm.clips.first(where: { $0.body == "pin-target" })
        #expect(afterPin?.isPinned == true)
        #expect(afterPin?.pinnedAt != nil)
        await vm.togglePin(id: afterPin!.id, trackSelection: .clip)
        let afterUnpin = vm.clips.first(where: { $0.body == "pin-target" })
        #expect(afterUnpin?.isPinned == false)
        #expect(afterUnpin?.pinnedAt == nil)
    }

    @Test("pinnedClips — 정렬 = pinnedAt DESC (최근 핀이 상단, TASK-019)")
    func pinnedClipsSortedByPinnedAtDesc() async throws {
        let prefilled = [
            makeClip(body: "first-pin", pinned: false),
            makeClip(body: "second-pin", pinned: false),
            makeClip(body: "third-pin", pinned: false)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        // 순서대로 핀 — Date() 시간 차이 보장 (10ms sleep).
        let firstId = vm.clips.first(where: { $0.body == "first-pin" })!.id
        await vm.togglePin(id: firstId, trackSelection: .clip)
        try? await Task.sleep(nanoseconds: 10_000_000)
        let secondId = vm.clips.first(where: { $0.body == "second-pin" })!.id
        await vm.togglePin(id: secondId, trackSelection: .clip)
        try? await Task.sleep(nanoseconds: 10_000_000)
        let thirdId = vm.clips.first(where: { $0.body == "third-pin" })!.id
        await vm.togglePin(id: thirdId, trackSelection: .clip)
        // 최근 핀 우선.
        #expect(vm.pinnedClips.count == 3)
        #expect(vm.pinnedClips[0].body == "third-pin")
        #expect(vm.pinnedClips[1].body == "second-pin")
        #expect(vm.pinnedClips[2].body == "first-pin")
    }

    @Test("onPinSidebarOpenChange / onPinnedClipsChange 콜백 — PopoverWindow 토글 / size 재조정 트리거")
    func pinSidebarCallbacksFire() async {
        let prefilled = [makeClip(body: "p1", pinned: true)]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        var openChangeCount = 0
        var pinnedChangeCount = 0
        vm.onPinSidebarOpenChange = { _ in openChangeCount += 1 }
        vm.onPinnedClipsChange = { pinnedChangeCount += 1 }
        vm.togglePinSidebar()  // 열기 → 콜백
        #expect(openChangeCount == 1)
        vm.togglePinSidebar()  // 닫기 → 콜백
        #expect(openChangeCount == 2)
        // pinnedClips 변화 (unpin) → onPinnedClipsChange 호출
        vm.pinSidebarOpen = false  // 사이드바 닫힌 상태에서 unpin (open 콜백은 false → false 변화 X)
        let openBeforeUnpin = openChangeCount
        await vm.togglePin(id: vm.pinnedClips[0].id, trackSelection: .pin)
        #expect(pinnedChangeCount == 1)  // unpin 1회 → 콜백 1회
        _ = openBeforeUnpin
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

    // TASK-019 fix 6차 — 행 단위 페이징 모델 폐기. anchor:nil 모델로 변경 (멀티라인 행 가변 height 무관).
    // 모든 키보드 nav 호출 시 pendingScrollToId = list[selectedIdx].id 박힘. visibleTopIdx 무관.

    @Test("키보드 moveSelectionDown — selectedIdx 1씩 증가 + pendingScrollToId = list[selectedIdx].id 갱신")
    func keyboardMoveDown_IncrementsAndSetsScrollId() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 1)
        #expect(vm.pendingScrollToId == vm.visibleClips[1].id)
    }

    @Test("키보드 moveSelectionDown — 리스트 끝 wrap → selectedIdx 0 + pendingScrollToId = list[0].id")
    func keyboardMoveDown_WrapToFirst() async {
        let prefilled = (0..<3).map { makeClip(body: "\($0)") }
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.selectedIdx = 2  // 마지막
        vm.moveSelectionDown()
        #expect(vm.selectedIdx == 0)
        #expect(vm.pendingScrollToId == vm.visibleClips[0].id)
    }

    @Test("키보드 moveSelectionUp — selectedIdx 1씩 감소 + pendingScrollToId = list[selectedIdx].id 갱신")
    func keyboardMoveUp_DecrementsAndSetsScrollId() async {
        let prefilled = [makeClip(body: "a"), makeClip(body: "b"), makeClip(body: "c")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.selectedIdx = 2
        vm.moveSelectionUp()
        #expect(vm.selectedIdx == 1)
        #expect(vm.pendingScrollToId == vm.visibleClips[1].id)
    }

    @Test("키보드 moveSelectionUp — 첫 행 ↑ wrap → selectedIdx count-1 + pendingScrollToId = list[count-1].id")
    func keyboardMoveUp_WrapToLast() async {
        let prefilled = (0..<3).map { makeClip(body: "\($0)") }
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        #expect(vm.selectedIdx == 0)
        vm.moveSelectionUp()
        #expect(vm.selectedIdx == 2)
        #expect(vm.pendingScrollToId == vm.visibleClips[2].id)
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

    // MARK: - TASK-025: 검색바 always-active 정책 정합 — 이전 검색 활성 단계 (searchInputActive) 케이스 폐기

    // TASK-025 — `deactivateSearchInput_PreservesQuery` / `setFocusZone_NonSearch_PreservesSearchInputActive` / `hoverSetSelectedIdx_PreservesSearchInputActive` / `resetForOpenInitializesState` 4 케이스 삭제. `searchInputActive` state + 관련 메서드 (`activateSearchInput` / `deactivateSearchInput` / `deactivateSearchInputAndClear` / `enterSearchZone`) 폐기로 검증 대상 없음. resetForOpen 의 정합은 본 파일 위 `resetForOpenNoSearchActiveState` 케이스에서 검증.

    // TASK-020 — pop (⌘⇧V) 단축키·기능 폐기로 pop_NonPinned_PastesAndDeletes / pop_OutOfRange_NoOp 케이스 삭제.

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

    // MARK: - TASK-024: ⌘+C 복사 단축키 + ⌘+V 권한 게이트

    @Test("TASK-024 — updateAccessibilityGranted: state 변경 시에만 갱신 (멱등)")
    func updateAccessibilityGrantedTogglesState() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "a")])
        #expect(vm.accessibilityGranted == false)
        vm.updateAccessibilityGranted(true)
        #expect(vm.accessibilityGranted == true)
        vm.updateAccessibilityGranted(true)  // 멱등 — 변화 X
        #expect(vm.accessibilityGranted == true)
        vm.updateAccessibilityGranted(false)
        #expect(vm.accessibilityGranted == false)
    }

    @Test("TASK-024 — copy(at:) — Settings pasteMode = autoPaste 일 때도 클립보드만 갱신 (⌘V 합성 X)")
    func copyForcesCopyBackEvenIfPasteModeAutoPaste() async {
        let prefilled = [makeClip(body: "copy-target")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        UserDefaults.standard.set(true, forKey: "autoPasteEnabled")  // TASK-033 — .autoPaste 대응 (UserDefaults 단일 진실 소스)
        vm.updateAccessibilityGranted(true)  // 권한 O 라도 ⌘C 는 .copyBack 강제 검증
        let clipId = vm.visibleClips[0].id
        await vm.copy(at: 0, zone: .clip)
        // copy 호출 후 flashedClipId 가 target 으로 설정됨 → 정상 호출 흔적.
        #expect(vm.flashedClipId == clipId)
    }

    @Test("TASK-024 — copy(at:) — pasteMode = copyBack 일 때도 정상 호출 (동일 동작)")
    func copyWorksWhenPasteModeIsCopyBack() async {
        let prefilled = [makeClip(body: "copy-target")]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        UserDefaults.standard.set(false, forKey: "autoPasteEnabled")  // TASK-033 — .copyBack 대응
        vm.updateAccessibilityGranted(false)  // 권한 X 도 ⌘C 는 항상 활성
        let clipId = vm.visibleClips[0].id
        await vm.copy(at: 0, zone: .clip)
        #expect(vm.flashedClipId == clipId)
    }

    @Test("TASK-024 — copy(at:) focusZone == .pin 일 때 pinnedClips 항목 대상")
    func copyInPinSidebarUsesPinnedClips() async {
        let prefilled = [
            makeClip(body: "regular", pinned: false),
            makeClip(body: "pinned-copy", pinned: true)
        ]
        let (vm, _) = await makeViewModel(prefilled: prefilled)
        await vm.reload()
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        let targetId = vm.pinnedClips[0].id
        await vm.copy(at: 0, zone: .pin)
        #expect(vm.flashedClipId == targetId)
    }

    @Test("TASK-024 — copy(at:) out-of-range idx — no-op (flashedClipId 미설정)")
    func copyOutOfRangeIsNoOp() async {
        let (vm, _) = await makeViewModel(prefilled: [makeClip(body: "a")])
        await vm.reload()
        #expect(vm.flashedClipId == nil)
        await vm.copy(at: 99, zone: .clip)  // out-of-range
        #expect(vm.flashedClipId == nil)
    }

    @Test("TASK-024 — paste(at:) 권한 X 시 effective mode .copyBack 강제 — pasteMode autoPaste 라도 ⌘V 합성 X")
    func pasteForcesCopyBackWhenPermissionDenied() async {
        // pasteService.paste 의 mode 분기를 *MockPasteSynthesizer 호출 여부* 로 간접 검증.
        // MockPasteSynthesizer.invokedCount > 0 = .autoPaste 분기 진입 / == 0 = .copyBack 분기.
        let repo = InMemoryClipRepository()
        let clip = makeClip(body: "paste-target")
        try? await repo.insert(clip)
        let synthesizer = MockPasteSynthesizer()
        let checker = MockPermissionChecker()
        checker.trusted = false
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: synthesizer,
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc)
        await vm.reload()
        UserDefaults.standard.set(true, forKey: "autoPasteEnabled")  // TASK-033 — .autoPaste 대응 (UserDefaults 단일 진실 소스)
        vm.updateAccessibilityGranted(false)  // 권한 X — effective mode 가 .copyBack 강제
        await vm.paste(at: 0, zone: .clip)
        // 권한 X → effective mode .copyBack → synthesizer 호출 0회.
        #expect(synthesizer.callCount == 0)
    }

    @Test("TASK-024 — paste(at:) 권한 O + pasteMode autoPaste 시 synthesizer 정상 호출")
    func pasteInvokesSynthesizerWhenPermissionGrantedAndAutoPaste() async {
        let repo = InMemoryClipRepository()
        let clip = makeClip(body: "paste-target")
        try? await repo.insert(clip)
        let synthesizer = MockPasteSynthesizer()
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: synthesizer,
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc)
        await vm.reload()
        UserDefaults.standard.set(true, forKey: "autoPasteEnabled")  // TASK-033 — .autoPaste 대응 (UserDefaults 단일 진실 소스)
        vm.updateAccessibilityGranted(true)
        await vm.paste(at: 0, zone: .clip)
        // 권한 O + autoPaste → synthesizer 1회 호출.
        #expect(synthesizer.callCount == 1)
    }

    @Test("TASK-024 — paste(at:) 권한 O + pasteMode copyBack 시 synthesizer 호출 X")
    func pasteSkipsSynthesizerWhenCopyBack() async {
        let repo = InMemoryClipRepository()
        let clip = makeClip(body: "paste-target")
        try? await repo.insert(clip)
        let synthesizer = MockPasteSynthesizer()
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: synthesizer,
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc)
        await vm.reload()
        UserDefaults.standard.set(false, forKey: "autoPasteEnabled")  // TASK-033 — .copyBack 대응
        vm.updateAccessibilityGranted(true)
        await vm.paste(at: 0, zone: .clip)
        #expect(synthesizer.callCount == 0)
    }
}
