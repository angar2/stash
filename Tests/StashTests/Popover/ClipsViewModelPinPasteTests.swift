// TASK-028 — 핀 사이드바 paste/copy zone 분기 회귀 차단. focusZone 후속 변경과 무관하게 호출 시점 `zone` 파라미터 만으로 paste/copy 대상이 결정됨을 검증.
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("ClipsViewModel.paste/copy zone 명시 파라미터 — TASK-028")
struct ClipsViewModelPinPasteTests {

    private func makeViewModel(prefilled: [Clip] = []) async -> (vm: ClipsViewModel, pasteboard: MockPasteboard) {
        let repo = InMemoryClipRepository()
        for clip in prefilled {
            _ = try? await repo.insert(clip)
        }
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteboard = MockPasteboard()
        let pasteSvc = PasteService(
            synthesizer: MockPasteSynthesizer(),
            pasteboard: pasteboard,
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc, fileClipService: MockFileClipService())
        return (vm, pasteboard)
    }

    private func makeClip(body: String, pinned: Bool = false, lastUsedAt: Date = Date()) -> Clip {
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
            createdAt: lastUsedAt,
            lastUsedAt: lastUsedAt
        )
    }

    /// 표준 셋업 — pinned 1 + 일반 2. 명시적 시간 차이로 visibleClips 정렬 (last_used_at DESC) 안정 확보:
    /// - regularB (now)        → visibleClips[0]
    /// - regularA (now - 1s)   → visibleClips[1]
    /// - pinned   (now - 2s)   → visibleClips[2]
    /// pinnedClips = [pinned] (단일).
    private func makeViewModelMixed() async -> (vm: ClipsViewModel, pinned: Clip, visibleFirst: Clip, pasteboard: MockPasteboard) {
        let now = Date()
        let pinned = makeClip(body: "pinned-target", pinned: true, lastUsedAt: now.addingTimeInterval(-2))
        let regularA = makeClip(body: "regular-A", pinned: false, lastUsedAt: now.addingTimeInterval(-1))
        let regularB = makeClip(body: "regular-B", pinned: false, lastUsedAt: now)
        let (vm, pasteboard) = await makeViewModel(prefilled: [pinned, regularA, regularB])
        await vm.reload()
        return (vm, pinned, regularB, pasteboard)
    }

    // MARK: - 1. paste — zone=.pin / focusZone=.clip 강제 → pinnedClips[0]

    @Test("paste(at:zone:.pin) — focusZone=.clip 강제 후에도 pinnedClips 대상 (본 버그 시나리오)")
    func pastePinZoneUsesPinnedClipsRegardlessOfFocusZone() async {
        let (vm, pinned, _, pasteboard) = await makeViewModelMixed()
        vm.focusZone = .clip  // 본 버그 시나리오 — hide() → collapsePinSidebar() → focusZone=.clip 모사
        vm.pinSelectedIdx = 0
        await vm.paste(at: 0, zone: .pin)
        // TASK-085 — paste flash 시각 피드백 폐기 정합, MockPasteboard 호출 흔적으로 zone 분기 검증.
        #expect(pasteboard.recordedSetString.last?.0 == pinned.body)
    }

    // MARK: - 2. paste — zone=.clip / focusZone=.pin → visibleClips[0]

    @Test("paste(at:zone:.clip) — focusZone=.pin 라도 visibleClips 대상")
    func pasteClipZoneUsesVisibleClipsRegardlessOfFocusZone() async {
        let (vm, _, visibleFirst, pasteboard) = await makeViewModelMixed()
        vm.focusZone = .pin
        vm.selectedIdx = 0
        await vm.paste(at: 0, zone: .clip)
        #expect(pasteboard.recordedSetString.last?.0 == visibleFirst.body)
    }

    // MARK: - 3. copy — zone=.pin / focusZone=.clip 강제 → pinnedClips[0]

    @Test("copy(at:zone:.pin) — focusZone=.clip 강제 후에도 pinnedClips 대상")
    func copyPinZoneUsesPinnedClipsRegardlessOfFocusZone() async {
        let (vm, pinned, _, pasteboard) = await makeViewModelMixed()
        vm.focusZone = .clip
        vm.pinSelectedIdx = 0
        await vm.copy(at: 0, zone: .pin)
        #expect(pasteboard.recordedSetString.last?.0 == pinned.body)
    }

    // MARK: - 4. copy — zone=.clip / focusZone=.pin → visibleClips[0]

    @Test("copy(at:zone:.clip) — focusZone=.pin 라도 visibleClips 대상")
    func copyClipZoneUsesVisibleClipsRegardlessOfFocusZone() async {
        let (vm, _, visibleFirst, pasteboard) = await makeViewModelMixed()
        vm.focusZone = .pin
        vm.selectedIdx = 0
        await vm.copy(at: 0, zone: .clip)
        #expect(pasteboard.recordedSetString.last?.0 == visibleFirst.body)
    }

    // MARK: - 5. paste — zone=.pin / idx out-of-range → silent no-op

    @Test("paste(at:zone:.pin) — idx out-of-range 시 silent no-op (pasteboard 미터치)")
    func pastePinZoneIdxOutOfRangeIsSilentNoOp() async {
        let (vm, _, _, pasteboard) = await makeViewModelMixed()
        #expect(pasteboard.changeCount == 0)
        await vm.paste(at: 99, zone: .pin)
        #expect(pasteboard.changeCount == 0)
    }

    // MARK: - 6. copy — zone=.pin / idx out-of-range → silent no-op

    @Test("copy(at:zone:.pin) — idx out-of-range 시 silent no-op (pasteboard 미터치)")
    func copyPinZoneIdxOutOfRangeIsSilentNoOp() async {
        let (vm, _, _, pasteboard) = await makeViewModelMixed()
        #expect(pasteboard.changeCount == 0)
        await vm.copy(at: 99, zone: .pin)
        #expect(pasteboard.changeCount == 0)
    }

    // MARK: - 7. 본 버그 직접 재현 시나리오 — focusZone=.pin → collapsePinSidebar() → paste(at:zone:.pin)

    @Test("paste(at:zone:.pin) — collapsePinSidebar() 직후 호출해도 pinnedClips 대상 (본 버그 직접 재현)")
    func pastePinZoneAfterCollapseSidebarStillPastesPinnedClip() async {
        let (vm, pinned, _, pasteboard) = await makeViewModelMixed()
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        // 본 버그 직접 재현: PopoverWindow.hide() → ClipsViewModel.collapsePinSidebar() → focusZone=.clip 변경.
        vm.collapsePinSidebar()
        #expect(vm.focusZone == .clip)  // collapse 후 focusZone 리셋 확인 (사전 조건).
        // 호출 시점 snapshot 으로 박은 zone=.pin 박힘. focusZone 후속 변경 영향 X.
        await vm.paste(at: 0, zone: .pin)
        #expect(pasteboard.recordedSetString.last?.0 == pinned.body)
    }
}
