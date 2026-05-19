// ClipsViewModel 4축 hook (focusZone / selectedIdx / pinSelectedIdx / activeRowFrameInPopover) + 200ms debounce 단위 테스트 (TASK-027)
@testable import stash
import Testing
import Foundation
import CoreGraphics

@Suite("ClipsViewModel — Clip Detail hook")
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

    /// Pin 다중파일용 별도 entries — `InMemoryClipRepository.insert` 의 file_paths_json dedup 회피 (multi 와 동일 entries 박으면 pinMulti 가 안 들어감).
    private func samplePinnedEntries() -> [ClipFileEntry] {
        [
            ClipFileEntry(originalPath: "/tmp/pinned-x.txt", filePath: "/Library/pinned-x.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/pinned-y.png", filePath: "/Library/pinned-y.png", isFileExternal: false)
        ]
    }

    /// Test 내부 invocation tracker — @MainActor 한정.
    @MainActor
    final class Tracker {
        var emissions: [ClipDetailRequest?] = []
        var emissionCount: Int { emissions.count }
        var lastEmission: ClipDetailRequest?? { emissions.last }
    }

    /// debounce 검증용 sleep — 300ms (200ms debounce + 100ms 마진).
    private func sleepDebounce() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    /// 모든 test setup 공통 — 다중파일 1 + 텍스트 1 + Pin 다중파일 1 시드.
    /// 주의: multi 와 pinMulti 의 entries 가 같으면 InMemoryClipRepository.insert dedup hit 으로 pinMulti 가 안 들어감.
    /// samplePinnedEntries() 로 별도 entries 사용해 dedup 회피.
    private func makeStandardViewModel() async -> (ClipsViewModel, [Clip]) {
        let multi = makeMultiFile(entries: sampleEntries())
        let text  = makeText(body: "hello")
        let pinMulti = makeMultiFile(entries: samplePinnedEntries(), pinned: true)
        let (vm, _) = await makeViewModel(prefilled: [multi, text, pinMulti])
        await vm.reload()
        return (vm, [multi, text, pinMulti])
    }

    private func attachTracker(_ vm: ClipsViewModel) -> Tracker {
        let tracker = Tracker()
        vm.onShowClipDetailChange = { req in
            tracker.emissions.append(req)
        }
        return tracker
    }

    // MARK: - 케이스

    @Test("다중파일 행 선택 + frame 설정 → 200ms 후 콜백 1회 (다중파일 clip 인자)")
    func selectMultiFileTriggersDetailAfterDebounce() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)

        // 다중파일 clip 의 visible idx 찾기 (정렬 룰 last_used_at DESC — multi는 lastUsed Date() 라 idx 0).
        let multiIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = multiIdx

        await sleepDebounce()

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count >= 1, "다중파일 행 선택 후 200ms 대기 시 콜백 1회 이상 발화. 실제 emissions=\(tracker.emissions)")
        #expect(nonNil.last?.clip.id == seeded[0].id)
        #expect(nonNil.last?.zone == .clip)
    }

    @Test("텍스트 클립 선택 → 콜백 nil + 추가 발화 없음")
    func selectTextClipDoesNotTriggerDetail() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)

        let textIdx = vm.visibleClips.firstIndex { $0.id == seeded[1].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 50, width: 380, height: 44)
        vm.selectedIdx = textIdx

        await sleepDebounce()

        // 모든 콜백 emission 이 nil 이어야 (텍스트 clip 은 Provider 매칭 X).
        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.isEmpty, "텍스트 클립 선택 시 non-nil 콜백 발화 X. 실제 non-nil=\(nonNil.count)")
    }

    @Test("빠른 연속 selectedIdx 변경 → 200ms 후 최종 1회만 발화 (debounce)")
    func rapidSelectionOnlyEmitsLastDebounce() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)

        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        // 0 → 1 → 0 → 1 → 0 빠른 연속 (모두 즉시, 200ms 이내).
        vm.selectedIdx = 1
        vm.selectedIdx = 0
        vm.selectedIdx = 1
        vm.selectedIdx = 0

        let initialEmissions = tracker.emissionCount
        await sleepDebounce()

        // 빠른 selectedIdx 변경마다 nil 발화 + 마지막에 1회 비-nil 발화 (또는 nil 유지).
        // 최종 selectedIdx == 0 (다중파일) — visibleClips[0]는 다중파일 (last_used DESC + multi 가 가장 최근).
        let nonNilEmissions = tracker.emissions.compactMap { $0 }
        #expect(nonNilEmissions.count <= 1, "debounce — 빠른 연속 후 최종 1회만 비-nil 발화. 실제=\(nonNilEmissions.count)")
        _ = initialEmissions
    }

    @Test("focusZone 전환 → 즉시 nil 콜백 + 0.3s 후 Pin 다중파일이면 발화")
    func focusZoneSwitchClearsDetailImmediately() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)

        // 활성 다중파일 행 선택 + 200ms 대기 → detail 활성 상태.
        let multiIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = multiIdx
        await sleepDebounce()
        tracker.emissions.removeAll()

        // focusZone .clip → .pin 전환 — Pin 다중파일이 pinSelectedIdx=0 자리에 있음.
        vm.focusZone = .pin

        // 즉시 nil 콜백 (현재 detail 닫음).
        #expect(tracker.emissions.contains(where: { $0 == nil }), "focusZone 전환 즉시 nil 콜백. 실제=\(tracker.emissions)")

        // frame 도 새로 게시 (Pin 사이드바 안 활성 행 frame 으로 가정).
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 30, width: 220, height: 44)
        await sleepDebounce()

        let nonNilAfter = tracker.emissions.compactMap { $0 }
        #expect(nonNilAfter.contains(where: { $0.zone == .pin }), "Pin 다중파일 활성 시 zone == .pin 콜백 발화. 실제 non-nil zones=\(nonNilAfter.map { $0.zone })")
    }

    @Test("resetForOpen → 콜백 nil 발화 + frame .zero 초기화")
    func resetForOpenClearsDetail() async throws {
        let (vm, _) = await makeStandardViewModel()
        let tracker = attachTracker(vm)

        // detail 활성 상태로 만들기.
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        await sleepDebounce()
        tracker.emissions.removeAll()

        // resetForOpen 호출.
        vm.resetForOpen()

        #expect(tracker.emissions.contains(where: { $0 == nil }), "resetForOpen 시 nil 콜백 발화. 실제=\(tracker.emissions)")
        #expect(vm.activeRowFrameInPopover == .zero)
    }

    @Test("same idx 다른 clip — reload 후 hook 재발화 (4축 clip.id 추적)")
    func clipChangeAtSameIdxRetriggersDetail() async throws {
        // 시드 = 텍스트 1개만. selectedIdx=0 일 때 detail 안 발화.
        let text = makeText(body: "first")
        let (vm, repo) = await makeViewModel(prefilled: [text])
        await vm.reload()
        let tracker = attachTracker(vm)

        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = 0
        await sleepDebounce()
        let initialNonNil = tracker.emissions.compactMap { $0 }
        #expect(initialNonNil.isEmpty, "텍스트 시점 non-nil 발화 X")

        // 0번 clip 을 다중파일로 대체 — repository 직접 조작 + reload.
        _ = try? await repo.delete(id: text.id)
        let multi = makeMultiFile(entries: sampleEntries())
        _ = try? await repo.insert(multi)
        await vm.reload()

        // reload 끝에 scheduleClipDetailUpdate 명시 호출 — 0번 자리에 새 다중파일 진입.
        await sleepDebounce()

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.contains(where: { $0.clip.id == multi.id }), "0번 자리에 다중파일 진입 시 hook 재발화. 실제 emitted ids=\(nonNil.map { $0.clip.id })")
    }

    @Test("activeRowFrame 변경 → hook 재발화 (4축 frame 추적)")
    func activeRowFrameChangeRetriggers() async throws {
        let (vm, seeded) = await makeStandardViewModel()
        let tracker = attachTracker(vm)

        let multiIdx = vm.visibleClips.firstIndex { $0.id == seeded[0].id } ?? 0
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 10, width: 380, height: 44)
        vm.selectedIdx = multiIdx
        await sleepDebounce()
        tracker.emissions.removeAll()

        // frame Y 변경 — 1pt 초과 변동이어야 didSet 발화 (PreferenceKey 미세 변동 무시 가드).
        vm.activeRowFrameInPopover = CGRect(x: 0, y: 100, width: 380, height: 44)
        await sleepDebounce()

        let nonNil = tracker.emissions.compactMap { $0 }
        #expect(nonNil.count >= 1, "frame 변경 후 hook 재발화. 실제=\(tracker.emissions.count)")
        #expect(nonNil.last?.rowFrameInPopover.origin.y == 100)
    }
}
