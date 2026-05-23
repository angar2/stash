// ClipsViewModel pinSidebarHoverExit 가드 closure 분기 단위 테스트 (TASK-062)
@testable import stash
import Testing
import Foundation

@Suite("ClipsViewModel — Pin sidebar hover exit guard (TASK-062)")
@MainActor
struct ClipsViewModelPinSidebarHoverExitTests {

    // MARK: - Helpers

    private func makeViewModel() async -> ClipsViewModel {
        let repo = InMemoryClipRepository()
        // 핀 클립 1개 시드 — expandPinSidebarImmediately 의 `pinnedClips.isEmpty` 가드 통과용.
        let pinned = Clip(
            id: UUID(), type: .text, body: "pinned-body",
            filePath: nil, isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: true,
            createdAt: Date(),
            lastUsedAt: Date(timeIntervalSinceNow: -10),
            pinnedAt: Date()
        )
        _ = try? await repo.insert(pinned)
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: MockPasteSynthesizer(),
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc, fileClipService: MockFileClipService())
        await vm.reload()
        return vm
    }

    /// `scheduleSidebarCloseIfNeeded` 의 `pinSidebarHoverOpenDelay` (200ms) + 여유 sleep.
    private func sleepCloseDelay() async {
        try? await Task.sleep(nanoseconds: UInt64((DesignTokens.Animation.pinSidebarHoverOpenDelay + 0.15) * 1_000_000_000))
    }

    // MARK: - 가드 closure 분기 검증

    @Test("TASK-062 — closure nil 시 hover exit → close 진행 (default 가드 없음)")
    func guardClosureNilFallsThroughToClose() async throws {
        let vm = await makeViewModel()
        vm.expandPinSidebarImmediately()
        #expect(vm.pinSidebarOpen == true, "expand 직후 pinSidebarOpen=true")
        vm.shouldRetainPinSidebarOnHoverExit = nil
        vm.pinSidebarHoverExit()
        await sleepCloseDelay()
        #expect(vm.pinSidebarOpen == false, "closure nil → close 진행 — pinSidebarOpen=false")
    }

    @Test("TASK-062 — closure return true → close 차단 (사이드바 잔존)")
    func guardClosureTrueBlocksClose() async throws {
        let vm = await makeViewModel()
        vm.expandPinSidebarImmediately()
        vm.shouldRetainPinSidebarOnHoverExit = { true }
        vm.pinSidebarHoverExit()
        await sleepCloseDelay()
        #expect(vm.pinSidebarOpen == true, "closure true → close 차단 — pinSidebarOpen=true 잔존 (TASK-030 자식 sub-panel 보호 의도)")
    }

    @Test("TASK-062 — closure return false → close 진행")
    func guardClosureFalseProceedsToClose() async throws {
        let vm = await makeViewModel()
        vm.expandPinSidebarImmediately()
        vm.shouldRetainPinSidebarOnHoverExit = { false }
        vm.pinSidebarHoverExit()
        await sleepCloseDelay()
        #expect(vm.pinSidebarOpen == false, "closure false → close 진행 — pinSidebarOpen=false (합집합 밖 이탈 시 동작)")
    }

    @Test("TASK-062 — close 발화 시 detail panel 동반 dismiss (pinSidebarOpen didSet → dismissClipDetail nil emit)")
    func closeAlsoDismissesDetailPanel() async throws {
        let vm = await makeViewModel()
        var emissions: [ClipDetailRequest?] = []
        vm.onShowClipDetailChange = { req in emissions.append(req) }
        vm.expandPinSidebarImmediately()
        emissions.removeAll()
        vm.shouldRetainPinSidebarOnHoverExit = { false }
        vm.pinSidebarHoverExit()
        await sleepCloseDelay()
        #expect(vm.pinSidebarOpen == false)
        // pinSidebarOpen=false didSet (ClipsViewModel.swift `pinSidebarOpen` didSet 안 TASK-055 단일 룰) → dismissClipDetail() 호출 → nil emit 1회 이상.
        #expect(emissions.contains(where: { $0 == nil }), "close 발화 시 nil emit (detail 동반 dismiss) 발화. 실제 emissions=\(emissions.count)")
    }
}
