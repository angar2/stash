// ClipsViewModel on-demand trigger API + close 단일 룰 단위 테스트 (TASK-027 / TASK-039 / TASK-055)
@testable import stash
import Testing
import Foundation
import CoreGraphics

@Suite("ClipsViewModel — Clip Detail trigger")
@MainActor
struct ClipsViewModelClipDetailTests {

    // MARK: - Helpers

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
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc, fileClipService: MockFileClipService())
        return (vm, repo)
    }

    private func makeText(body: String) -> Clip {
        Clip(
            id: UUID(), type: .text, body: body,
            filePath: nil, isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: false,
            createdAt: Date(), lastUsedAt: Date()
        )
    }

    private func makeMultiFile(entries: [ClipFileEntry], pinned: Bool = false) -> Clip {
        let json = (try? ClipFileEntry.encodeJSON(entries)) ?? "[]"
        return Clip(
            id: UUID(), type: .file, body: nil,
            filePath: nil, isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil,
            sourceAppBundleId: nil, isPinned: pinned,
            createdAt: Date(),
            lastUsedAt: pinned ? Date(timeIntervalSinceNow: -10) : Date(),
            pinnedAt: pinned ? Date() : nil,
            filePathsJson: json
        )
    }

    private func sampleEntries() -> [ClipFileEntry] {
        [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/a.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/b.png", isFileExternal: false)
        ]
    }

    private func samplePinnedEntries() -> [ClipFileEntry] {
        [
            ClipFileEntry(originalPath: "/tmp/pinned-x.txt", filePath: "/Library/pinned-x.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/pinned-y.png", filePath: "/Library/pinned-y.png", isFileExternal: false)
        ]
    }

    /// hover 임계 + 짧은 마진 sleep. Constants.clipDetailHoverDelaySeconds (2.0초) 기반.
    private func sleepHoverDelay() async {
        try? await Task.sleep(nanoseconds: UInt64((Constants.clipDetailHoverDelaySeconds + 0.3) * 1_000_000_000))
    }

    /// hover 임계 미만 짧은 sleep (cancel 검증용 — emit 발화 X 확인).
    private func sleepHoverBelow() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    @MainActor
    final class Tracker {
        var emissions: [ClipDetailRequest?] = []
        var emissionCount: Int { emissions.count }
        var lastEmission: ClipDetailRequest?? { emissions.last }
    }

    private func makeStandardViewModel() async -> (ClipsViewModel, [Clip]) {
        let multi = makeMultiFile(entries: sampleEntries())
        let text  = makeText(body: "hello")
        let pinMulti = makeMultiFile(entries: samplePinnedEntries(), pinned: true)
        let (vm, _) = await makeViewModel(prefilled: [multi, text, pinMulti])
        await vm.reload()
        // ignoreHoverUntil grace period 진입 차단 (popover 열림 직후 200ms 자동 차단) — 테스트에서는 즉시 hover 진입 허용.
        // 격리 시드 직후 ignoreHoverUntil = .distantPast → setSelectedIdx / hoverEnterRow 모두 즉시 정상 진입.
        return (vm, [multi, text, pinMulti])
    }

    private func attachTracker(_ vm: ClipsViewModel) -> Tracker {
        let tracker = Tracker()
        vm.onShowClipDetailChange = { req in
            tracker.emissions.append(req)
        }
        return tracker
    }

    // MARK: - TASK-055 — default closed 정책

    @Test("TASK-055 — popover 첫 오픈 (resetForOpen) 직후 detail 미표시 (default closed)")
    func popoverOpenDetailClosedByDefault() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.resetForOpen()
        #expect(vm.clipDetailVisible == false)
        // resetForOpen 시 dismissClipDetail() 호출 → nil emit 발화.
        #expect(tracker.emissions.allSatisfy { $0 == nil }, "resetForOpen 직후 emissions 모두 nil. 실제=\(tracker.emissions)")
    }

    @Test("TASK-055 — selectedIdx 변경만으로는 detail 미표시 (자동 emit 정책 폐기)")
    func selectedIdxChangeAloneDoesNotEmit() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        // selectedIdx 변경 — close 단일 룰로 dismissClipDetail 호출 (nil emit) / 자동 emit X.
        vm.selectedIdx = 1
        try? await Task.sleep(nanoseconds: 300_000_000)
        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.isEmpty, "selectedIdx 변경만으로는 non-nil emit 발화 X. 실제 non-nil=\(nonNil.count)")
        #expect(vm.clipDetailVisible == false)
    }

    // MARK: - TASK-055 — triggerClipDetail 진입점

    @Test("TASK-055 — triggerClipDetail (다중파일 활성 시) → 비-nil emit + clipDetailVisible=true")
    func triggerClipDetailEmitsRequestForMultiFile() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        let multiIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = multiIdx
        tracker.emissions.removeAll()

        vm.triggerClipDetail()

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count == 1, "triggerClipDetail 1회 → 비-nil emit 1회. 실제=\(nonNil.count)")
        #expect(nonNil.last?.clip.id == seeded[0].id)
        #expect(nonNil.last?.zone == .clip)
        #expect(vm.clipDetailVisible == true)
    }

    @Test("TASK-055 — triggerClipDetail (텍스트 활성 시) → 비-nil emit (4 Provider 매칭)")
    func triggerClipDetailEmitsRequestForText() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        let textIdx = vm.visibleClips.firstIndex { $0.id == seeded[1].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 50, width: 380, height: 44)
        vm.selectedIdx = textIdx
        tracker.emissions.removeAll()

        vm.triggerClipDetail()

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count == 1)
        #expect(nonNil.last?.clip.id == seeded[1].id)
        #expect(nonNil.last?.clip.type == .text)
    }

    @Test("TASK-055 — triggerClipDetail 재호출 (이미 visible) → toggle close (nil emit + visible=false)")
    func triggerClipDetailToggleClose() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        vm.triggerClipDetail()
        #expect(vm.clipDetailVisible == true)
        tracker.emissions.removeAll()

        // 2번째 trigger — toggle close 진입.
        vm.triggerClipDetail()

        #expect(vm.clipDetailVisible == false)
        #expect(tracker.emissions.last.map { $0 == nil } == true, "toggle close 시 nil emit. 실제 last=\(String(describing: tracker.emissions.last))")
    }

    @Test("TASK-055 — triggerClipDetail (frame 미게시) → no-op (emit 발화 X)")
    func triggerClipDetailFrameMissingNoOp() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        // activeRowFrameInPopover == .zero (미게시).
        vm.selectedIdx = 0
        tracker.emissions.removeAll()
        vm.triggerClipDetail()
        // frame 미게시라 emit 발화 X. clipDetailVisible 도 false 유지.
        #expect(tracker.emissions.compactMap { $0 }.isEmpty, "frame 미게시 시 비-nil emit X")
        #expect(vm.clipDetailVisible == false)
    }

    // MARK: - TASK-055 — close 단일 룰

    @Test("TASK-055 — selectedIdx 변경 (이미 visible) → 즉시 close (close 단일 룰)")
    func selectedIdxChangeClosesDetailIfVisible() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        vm.triggerClipDetail()
        #expect(vm.clipDetailVisible == true)
        tracker.emissions.removeAll()

        // 행 변경.
        vm.selectedIdx = 1

        #expect(vm.clipDetailVisible == false)
        #expect(tracker.emissions.last.map { $0 == nil } == true, "selectedIdx 변경 즉시 nil emit. 실제 last=\(String(describing: tracker.emissions.last))")
    }

    @Test("TASK-055 — focusZone 전환 → 즉시 close (close 단일 룰)")
    func focusZoneChangeClosesDetail() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        vm.triggerClipDetail()
        #expect(vm.clipDetailVisible == true)
        tracker.emissions.removeAll()

        // focusZone 전환.
        vm.focusZone = .settings

        #expect(vm.clipDetailVisible == false)
        #expect(tracker.emissions.last.map { $0 == nil } == true)
    }

    @Test("TASK-055 — dismissClipDetail 명시 호출 → nil emit + visible=false")
    func dismissClipDetailEmitsNil() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        vm.triggerClipDetail()
        tracker.emissions.removeAll()

        vm.dismissClipDetail()

        #expect(vm.clipDetailVisible == false)
        #expect(tracker.emissions.last.map { $0 == nil } == true)
    }

    @Test("TASK-055 — resetForOpen → 명시 close (frame .zero + visible=false)")
    func resetForOpenClearsDetail() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        vm.triggerClipDetail()
        #expect(vm.clipDetailVisible == true)
        tracker.emissions.removeAll()

        vm.resetForOpen()

        #expect(vm.clipDetailVisible == false)
        #expect(vm.activeRowFrameInPopover == .zero)
        #expect(tracker.emissions.contains(where: { $0 == nil }))
    }

    // MARK: - TASK-055 — activeRowFrame 추적 (이미 visible 시 재계산)

    @Test("TASK-055 — activeRowFrame 변경 (visible 아닌 시) → no-op (emit X)")
    func activeRowFrameChangeWhileHiddenNoOp() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.selectedIdx = 0
        tracker.emissions.removeAll()

        // visible 아닌 상태에서 frame 변경.
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 100, width: 380, height: 44)

        #expect(tracker.emissions.compactMap { $0 }.isEmpty, "visible 아닌 상태에서 frame 변경은 emit 발화 X")
    }

    @Test("TASK-055 — activeRowFrame 변경 (이미 visible) → 새 frame 으로 재계산 emit (panel 위치 따라감)")
    func activeRowFrameChangeWhileVisibleReemits() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        vm.triggerClipDetail()
        #expect(vm.clipDetailVisible == true)
        tracker.emissions.removeAll()

        // frame Y 변경 (threshold 1pt 초과).
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 100, width: 380, height: 44)

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count >= 1, "visible 상태에서 frame 변경 시 재계산 emit. 실제=\(nonNil.count)")
        #expect(nonNil.last?.rowFrameInPopover.origin.y == 100)
    }

    // MARK: - TASK-055 — hover 트리거

    @Test("TASK-055 — hoverEnterRow → 임계 (Constants.clipDetailHoverDelaySeconds) 후 triggerClipDetail 자동 발화")
    func hoverEnterSchedulesTrigger() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        let multiIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = multiIdx
        tracker.emissions.removeAll()

        vm.hoverEnterRow(id: seeded[0].id)
        await sleepHoverDelay()

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count >= 1, "hover 임계 도달 후 자동 trigger 발화. 실제=\(nonNil.count)")
        #expect(vm.clipDetailVisible == true)
    }

    @Test("TASK-055 — hoverExitRow (같은 row) → task cancel (임계 sleep 후 emit 발화 X)")
    func hoverExitSameRowCancels() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        let multiIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = multiIdx
        tracker.emissions.removeAll()

        vm.hoverEnterRow(id: seeded[0].id)
        await sleepHoverBelow()  // 임계 미만 sleep
        vm.hoverExitRow(id: seeded[0].id)
        await sleepHoverDelay()  // 추가 sleep 후에도 trigger 발화 X

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.isEmpty, "hover exit 후 trigger 발화 X. 실제=\(nonNil.count)")
        #expect(vm.clipDetailVisible == false)
    }

    @Test("TASK-055 — hoverEnterRow (다른 row) → 기존 task cancel + 새 task 시작 (임계 후 새 행 trigger)")
    func hoverEnterDifferentRowCancelsAndRestarts() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)
        // 시드 = 다중파일 + 텍스트 + Pin 다중파일. 본체 visibleClips 안 두 행 id 박음.
        let firstIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        let secondIdx = vm.visibleClips.firstIndex { $0.id == seeded[1].id } ?? 1
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = firstIdx
        tracker.emissions.removeAll()

        // 1행 hover 진입 — task 시작.
        vm.hoverEnterRow(id: seeded[0].id)
        await sleepHoverBelow()  // 임계 미만 sleep
        // 임계 도달 전 다른 행 hover 진입 — 기존 task cancel + 새 task 시작.
        // selectedIdx 변경은 *trigger* 전 단계라 didSet 의 dismissClipDetail 영향 X (clipDetailVisible=false 상태).
        vm.selectedIdx = secondIdx
        vm.hoverEnterRow(id: seeded[1].id)
        await sleepHoverDelay()

        // 임계 도달 후 trigger 발화 — 새 행 (텍스트, Provider 매칭) emit.
        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count >= 1, "다른 행 hover 진입 후 임계 도달 시 새 행 trigger 발화. 실제=\(nonNil.count)")
        #expect(nonNil.last?.clip.id == seeded[1].id, "마지막 emit = 두 번째 행 (텍스트)")
        #expect(vm.clipDetailVisible == true)
    }
}
