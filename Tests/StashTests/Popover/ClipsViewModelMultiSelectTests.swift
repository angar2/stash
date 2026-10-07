// ClipsViewModel 다중 선택 상태 전이 — 단위 테스트 (TASK-099, Test Plan #6~#7)
//
// 선택 상태는 순서 칩 · 프리뷰 · 묶음 실행이 모두 참조하는 단일 진실이라, 전이 규칙이 어긋나면
// 화면과 실행 결과가 동시에 틀어진다. 화면·붙여넣기 자체는 여기서 검증하지 않는다 (실기 검수 몫).
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("ClipsViewModel 다중 선택 (TASK-099)", .serialized)
struct ClipsViewModelMultiSelectTests {

    private struct Harness {
        let vm: ClipsViewModel
        let repo: InMemoryClipRepository
        let pasteboard: MockPasteboard
        let synthesizer: MockPasteSynthesizer
    }

    private func makeHarness(prefilled: [Clip] = [], autoPaste: Bool = true) async -> Harness {
        let repo = InMemoryClipRepository()
        for clip in prefilled {
            _ = try? await repo.insert(clip)
        }
        let checker = MockPermissionChecker()
        checker.trusted = true
        let pasteboard = MockPasteboard()
        let synthesizer = MockPasteSynthesizer()
        let pasteSvc = PasteService(
            synthesizer: synthesizer,
            pasteboard: pasteboard,
            repository: repo,
            permissionService: PermissionService(checker: checker),
            // 실제로 수백 ms 를 자면 병렬로 도는 *임계 시간에 의존하는 다른 테스트* 들을 굶긴다.
            sequentialDelay: .milliseconds(1)
        )
        // `clipsPerPage` / `autoFitClipListHeight` 는 **일부러 건드리지 않는다** — 본 스위트는 페이지 점프도
        // 높이 계산도 검증하지 않는데, 같은 키를 읽는 다른 스위트(page jump 테스트)와 병렬로 돌면서
        // 서로의 값을 덮어써 엉뚱한 테스트를 떨어뜨린다.
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
        let vm = ClipsViewModel(
            repository: repo,
            pasteService: pasteSvc,
            fileClipService: MockFileClipService()
        )
        vm.updateAccessibilityGranted(true)
        // *바로 붙여넣기* 설정은 여러 스위트가 공유하는 UserDefaults 키다. 스위트가 병렬로 돌아
        // 조회 시점 값이 남의 것일 수 있으므로, 전역을 읽지 말고 이 테스트가 정한 값을 쓰게 한다.
        vm.autoPasteEnabledProvider = { autoPaste }
        return Harness(vm: vm, repo: repo, pasteboard: pasteboard, synthesizer: synthesizer)
    }

    private func makeViewModel(prefilled: [Clip] = []) async -> (ClipsViewModel, InMemoryClipRepository) {
        let harness = await makeHarness(prefilled: prefilled)
        return (harness.vm, harness.repo)
    }

    // MARK: - 토글 (Test Plan #6)

    @Test("토글 — 선택 순서 유지, 재입력은 해제, 뒤 순번이 당겨짐")
    func toggleKeepsOrderAndRenumbersOnRelease() async {
        let a = ClipFixture.makeText(body: "A")
        let b = ClipFixture.makeText(body: "B")
        let c = ClipFixture.makeText(body: "C")
        let (vm, _) = await makeViewModel(prefilled: [a, b, c])
        await vm.reload()

        vm.toggleMultiSelect(id: a.id)
        vm.toggleMultiSelect(id: b.id)
        vm.toggleMultiSelect(id: c.id)
        #expect(vm.multiSelection == [a.id, b.id, c.id])
        #expect(vm.multiSelectOrdinal(for: c.id) == 3)

        // 가운데(B) 해제 → 뒤 항목(C)의 순번이 3 → 2 로 당겨져야 한다.
        vm.toggleMultiSelect(id: b.id)
        #expect(vm.multiSelection == [a.id, c.id])
        #expect(vm.multiSelectOrdinal(for: a.id) == 1)
        #expect(vm.multiSelectOrdinal(for: c.id) == 2)
        #expect(vm.multiSelectOrdinal(for: b.id) == nil)
    }

    /// 선택 순서는 목록 나열 순서와 무관하다 — 이게 어긋나면 연결 결과 전체가 틀어진다.
    @Test("선택 순서가 목록 순서를 따르지 않는다")
    func selectionOrderIndependentOfListOrder() async {
        let 가 = ClipFixture.makeText(body: "가")
        let 나 = ClipFixture.makeText(body: "나")
        let 다 = ClipFixture.makeText(body: "다")
        let 라 = ClipFixture.makeText(body: "라")
        let (vm, _) = await makeViewModel(prefilled: [가, 나, 다, 라])
        await vm.reload()

        for id in [가.id, 다.id, 라.id, 나.id] { vm.toggleMultiSelect(id: id) }
        #expect(vm.multiSelectedClips.map { $0.body } == ["가", "다", "라", "나"])

        let separator = MultiPasteComposer.resolveSeparator(", ")
        #expect(MultiPasteComposer.joinedText(clips: vm.multiSelectedClips, separator: separator) == "가, 다, 라, 나")
    }

    @Test("존재하지 않는 id 토글은 무시 (사라진 클립을 가리키는 stale 콜백 방어)")
    func togglingUnknownIdIsIgnored() async {
        let a = ClipFixture.makeText(body: "A")
        let (vm, _) = await makeViewModel(prefilled: [a])
        await vm.reload()

        vm.toggleMultiSelect(id: UUID())
        #expect(vm.multiSelection.isEmpty)
    }

    // MARK: - 커서 행 토글 (fix-4 — 선택 단축키가 실제로 가리키는 대상)

    /// 선택 단축키의 대상 판정. `dispatch` 가 아니라 뷰모델이 하므로 여기서 잡을 수 있다
    /// (fix-1 에서 흐름이 dispatch 안에만 있어 단위 테스트가 통째로 비껴간 전례).
    @Test("커서 행 토글 — 히스토리 zone 은 히스토리 커서를 집는다")
    func activeRowToggleUsesHistoryCursor() async {
        let a = ClipFixture.makeText(body: "A")
        let b = ClipFixture.makeText(body: "B")
        let (vm, _) = await makeViewModel(prefilled: [a, b])
        await vm.reload()

        vm.focusZone = .clip
        vm.selectedIdx = 1
        #expect(vm.toggleMultiSelectAtActiveRow())
        #expect(vm.multiSelectedClips.map { $0.body } == [vm.visibleClips[1].body])
    }

    /// fix-4 의 핵심. 이전에는 `focusZone == .clip` 가드에 막혀 사이드바에서 아무 일도 일어나지 않았다.
    @Test("커서 행 토글 — Pin 사이드바 zone 은 사이드바 커서를 집는다 (fix-4)")
    func activeRowToggleUsesPinCursor() async {
        let plain = ClipFixture.makeText(body: "일반")
        let pinned = ClipFixture.makeText(body: "핀", isPinned: true)
        let (vm, _) = await makeViewModel(prefilled: [plain, pinned])
        await vm.reload()
        // 사이드바에 실제로 항목이 있어야 이 테스트가 의미를 갖는다.
        #expect(vm.pinnedClips.count == 1)

        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        #expect(vm.toggleMultiSelectAtActiveRow())
        #expect(vm.multiSelectedClips.map { $0.body } == ["핀"])

        // 재입력은 해제 — 히스토리와 같은 토글 규칙.
        #expect(vm.toggleMultiSelectAtActiveRow())
        #expect(vm.multiSelection.isEmpty)
    }

    /// 핀 클립은 히스토리와 사이드바 **양쪽에 동시에 보인다**. 선택은 id 기준이라 한 건이어야 한다 —
    /// 두 목록을 각각 세면 같은 클립이 두 번 붙는다.
    @Test("커서 행 토글 — 같은 핀 클립을 양쪽에서 집어도 선택은 한 건 (두 번째는 해제)")
    func pinnedClipSelectedOnceAcrossBothLists() async {
        let pinned = ClipFixture.makeText(body: "핀", isPinned: true)
        let (vm, _) = await makeViewModel(prefilled: [pinned])
        await vm.reload()
        #expect(vm.visibleClips.contains { $0.id == pinned.id })
        #expect(vm.pinnedClips.contains { $0.id == pinned.id })

        vm.focusZone = .clip
        vm.selectedIdx = 0
        vm.toggleMultiSelectAtActiveRow()
        #expect(vm.multiSelection == [pinned.id])
        #expect(vm.multiSelectOrdinal(for: pinned.id) == 1)

        // 사이드바에서 같은 클립을 집으면 *추가* 가 아니라 해제다.
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        vm.toggleMultiSelectAtActiveRow()
        #expect(vm.multiSelection.isEmpty)
    }

    @Test("커서 행 토글 — 설정 zone·커서 범위 밖은 무동작 (이벤트 소비는 호출처 책임)")
    func activeRowToggleIgnoresNonRowZones() async {
        let a = ClipFixture.makeText(body: "A")
        let (vm, _) = await makeViewModel(prefilled: [a])
        await vm.reload()

        vm.focusZone = .settings
        #expect(vm.toggleMultiSelectAtActiveRow() == false)
        #expect(vm.multiSelection.isEmpty)

        // 핀이 하나도 없는 상태의 사이드바 zone — 커서가 가리킬 행이 없다.
        vm.focusZone = .pin
        vm.pinSelectedIdx = 0
        #expect(vm.pinnedClips.isEmpty)
        #expect(vm.toggleMultiSelectAtActiveRow() == false)
        #expect(vm.multiSelection.isEmpty)

        // 히스토리 커서가 범위 밖인 경우.
        vm.focusZone = .clip
        vm.selectedIdx = 99
        #expect(vm.toggleMultiSelectAtActiveRow() == false)
        #expect(vm.multiSelection.isEmpty)
    }

    @Test("전체 해제 — 선택·프리뷰가 함께 비워짐")
    func clearRemovesEverything() async {
        let a = ClipFixture.makeText(body: "A")
        let b = ClipFixture.makeText(body: "B")
        let (vm, _) = await makeViewModel(prefilled: [a, b])
        await vm.reload()

        vm.toggleMultiSelect(id: a.id)
        vm.toggleMultiSelect(id: b.id)
        #expect(vm.multiPastePreview != nil)

        vm.clearMultiSelection()
        #expect(vm.multiSelection.isEmpty)
        #expect(vm.multiSelectedClips.isEmpty)
        #expect(vm.multiPastePreview == nil)
    }

    @Test("popover 재진입(resetForOpen) 시 선택 초기화")
    func resetForOpenClearsSelection() async {
        let a = ClipFixture.makeText(body: "A")
        let (vm, _) = await makeViewModel(prefilled: [a])
        await vm.reload()

        vm.toggleMultiSelect(id: a.id)
        #expect(vm.multiSelection.count == 1)

        vm.resetForOpen()
        #expect(vm.multiSelection.isEmpty)
    }

    // MARK: - 삭제 시 자동 제외 (Test Plan #7)

    @Test("선택 클립 삭제 — 선택 목록에서 자동 제외 + 프리뷰 즉시 갱신")
    func deletingSelectedClipPrunesSelection() async {
        let a = ClipFixture.makeText(body: "AAA")
        let b = ClipFixture.makeText(body: "BBB")
        let (vm, _) = await makeViewModel(prefilled: [a, b])
        await vm.reload()

        vm.toggleMultiSelect(id: a.id)
        vm.toggleMultiSelect(id: b.id)
        #expect(vm.multiSelection == [a.id, b.id])

        // B 를 삭제한다 (목록에서 B 의 현재 위치를 찾아 그 idx 로).
        let bIdx = try? #require(vm.visibleClips.firstIndex(where: { $0.id == b.id }))
        await vm.delete(at: bIdx ?? 0)

        #expect(vm.multiSelection == [a.id])
        #expect(vm.multiSelectedClips.map { $0.body } == ["AAA"])
        // 프리뷰에서도 사라진 클립의 본문이 남아 있으면 안 된다.
        #expect(vm.multiPastePreview?.body.contains("BBB") == false)
    }

    @Test("전체 삭제 — 삭제된 클립만 선택에서 제외 (핀은 남음)")
    func deleteAllPrunesOnlyDeleted() async {
        let pinned = ClipFixture.makeText(body: "PINNED", isPinned: true)
        let plain = ClipFixture.makeText(body: "PLAIN")
        let (vm, _) = await makeViewModel(prefilled: [pinned, plain])
        await vm.reload()

        vm.toggleMultiSelect(id: pinned.id)
        vm.toggleMultiSelect(id: plain.id)
        #expect(vm.multiSelection.count == 2)

        await vm.deleteAllExceptPinned()
        #expect(vm.multiSelection == [pinned.id])
    }

    // MARK: - 검색 중 유지

    /// 검색은 `clips` 를 결과로 통째 갈아끼운다. 선택이 조회 결과에 의존하면 필터 순간 통째로 날아간다.
    @Test("검색으로 목록에서 빠져도 선택·프리뷰 유지, 검색 해제 후 복귀")
    func selectionSurvivesSearchFiltering() async {
        let hello = ClipFixture.makeText(body: "hello")
        let world = ClipFixture.makeText(body: "world")
        let (vm, _) = await makeViewModel(prefilled: [hello, world])
        await vm.reload()

        vm.toggleMultiSelect(id: hello.id)
        vm.toggleMultiSelect(id: world.id)

        // "hello" 로 검색 → world 가 목록에서 사라진다.
        vm.searchQuery = "hello"
        await vm.performSearch()
        #expect(vm.visibleClips.contains { $0.id == world.id } == false)
        // 그래도 선택과 프리뷰는 그대로다.
        #expect(vm.multiSelection == [hello.id, world.id])
        #expect(vm.multiSelectedClips.map { $0.body } == ["hello", "world"])

        // 검색 해제 후에도 순서 그대로.
        vm.searchQuery = ""
        await vm.performSearch()
        #expect(vm.multiSelection == [hello.id, world.id])
    }

    // MARK: - 묶음 실행 (Test Plan #8~#9)

    @Test("텍스트 묶음 복사 — 연결 결과가 클립보드에 + 새 텍스트 클립이 최상단에 등록")
    func textBundleCopyRegistersNewClip() async throws {
        let 가 = ClipFixture.makeText(body: "가")
        let 나 = ClipFixture.makeText(body: "나")
        let 다 = ClipFixture.makeText(body: "다")
        let h = await makeHarness(prefilled: [가, 나, 다])
        // makeHarness 가 연결자 키를 지우므로 **그 뒤에** 설정해야 한다.
        UserDefaults.standard.set(", ", forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
        defer { UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.multiPasteSeparator) }
        await h.vm.reload()

        // 목록 순서와 다르게 다 → 가 → 나 로 고른다.
        for id in [다.id, 가.id, 나.id] { h.vm.toggleMultiSelect(id: id) }
        await h.vm.runMultiPaste(.copy)

        // 클립보드에 연결 결과 1건.
        let written = h.pasteboard.recordedSetString.last
        #expect(written?.0 == "다, 가, 나")
        #expect(written?.1 == .string)
        // 복사는 붙여넣기 합성을 하지 않는다.
        #expect(h.synthesizer.callCount == 0)

        // 새 클립이 등록되고 선택은 비워진다.
        let stored = try await h.repo.fetchAll()
        #expect(stored.contains { $0.type == .text && $0.body == "다, 가, 나" })
        #expect(h.vm.multiSelection.isEmpty)
    }

    @Test("텍스트 묶음 붙여넣기 — 자동 붙여넣기 모드에서 ⌘V 합성 1회")
    func textBundlePasteSynthesizesOnce() async {
        let a = ClipFixture.makeText(body: "A")
        let b = ClipFixture.makeText(body: "B")
        let h = await makeHarness(prefilled: [a, b], autoPaste: true)
        await h.vm.reload()

        h.vm.toggleMultiSelect(id: a.id)
        h.vm.toggleMultiSelect(id: b.id)
        await h.vm.runMultiPaste(.paste)

        // 묶음은 *한 번* 붙는다 — 항목 수만큼 합성하면 같은 내용이 여러 번 들어간다.
        #expect(h.synthesizer.callCount == 1)
    }

    @Test("파일 묶음 — 파일 URL 배열 기록 + 새 다중 파일 클립 등록 (선택 순서 유지)")
    func fileBundleRegistersMultiFileClip() async throws {
        let pdf = ClipFixture.makeFile(originalPath: "/tmp/보고서.pdf", filePath: "/Library/copies/보고서.pdf")
        let png = ClipFixture.makeImage(filePath: "/Library/copies/screenshot.png")
        let h = await makeHarness(prefilled: [pdf, png])
        await h.vm.reload()

        // png → pdf 순서로 고른다 (목록 순서와 반대).
        h.vm.toggleMultiSelect(id: png.id)
        h.vm.toggleMultiSelect(id: pdf.id)
        await h.vm.runMultiPaste(.paste)

        let urls = try #require(h.pasteboard.recordedWriteFileURLs.last)
        #expect(urls.map(\.path) == ["/Library/copies/screenshot.png", "/tmp/보고서.pdf"])

        let stored = try await h.repo.fetchAll()
        let bundle = try #require(stored.first { $0.isMultiFile && $0.id != pdf.id && $0.id != png.id })
        let entries = try #require(bundle.fileEntries)
        // 등록 클립도 *선택 순서* 를 그대로 담아야 한다 (다시 붙여넣을 때 순서가 유지되도록).
        let effective = entries.map { $0.originalPath.isEmpty ? $0.filePath : $0.originalPath }
        #expect(effective == ["/Library/copies/screenshot.png", "/tmp/보고서.pdf"])
        #expect(h.vm.multiSelection.isEmpty)
    }

    @Test("파일 묶음 등록 — 단일 클립의 원본 북마크와 묶음 항목의 북마크를 그대로 이어받는다 (TASK-113)")
    func fileBundleCarriesBookmarks() async throws {
        let single = Clip(
            id: UUID(), type: .file, body: nil,
            filePath: "/Library/copies/x.pdf", isFileExternal: false,
            fileOriginalPath: "/tmp/x.pdf", fileBookmark: Data([7]),
            sourceAppBundleId: nil, isPinned: false, createdAt: Date(), lastUsedAt: Date()
        )
        let multi = ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/copies/a.txt", isFileExternal: false, bookmark: Data([8])),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/copies/b.png", isFileExternal: false)
        ])
        let h = await makeHarness(prefilled: [single, multi])
        await h.vm.reload()

        h.vm.toggleMultiSelect(id: single.id)
        h.vm.toggleMultiSelect(id: multi.id)
        await h.vm.runMultiPaste(.copy)

        let stored = try await h.repo.fetchAll()
        let bundle = try #require(stored.first { $0.isMultiFile && $0.id != multi.id })
        #expect(bundle.accessBookmarks == [Data([7]), Data([8]), nil])
    }

    @Test("선택 1개 붙여넣기 — 묶음 로직을 타도 결과는 그 텍스트 그대로")
    func singleSelectionBehavesLikeSingleClip() async {
        let only = ClipFixture.makeText(body: "혼자")
        let h = await makeHarness(prefilled: [only])
        await h.vm.reload()

        h.vm.toggleMultiSelect(id: only.id)
        await h.vm.runMultiPaste(.paste)

        #expect(h.pasteboard.recordedSetString.last?.0 == "혼자")
    }

    // MARK: - 혼합 계열 차단 (Test Plan #21)

    @Test("혼합 선택 복사 — 실행 없음 + 선택 유지 (단일 산출물 없음)")
    func mixedCopyIsBlocked() async {
        let text = ClipFixture.makeText(body: "가")
        let file = ClipFixture.makeFile()
        let h = await makeHarness(prefilled: [text, file])
        await h.vm.reload()

        h.vm.toggleMultiSelect(id: text.id)
        h.vm.toggleMultiSelect(id: file.id)

        #expect(h.vm.multiPasteBlockReason(for: .copy) == .mixedCopyUnsupported)
        await h.vm.runMultiPaste(.copy)

        // 아무것도 기록되지 않고 선택도 그대로여야 한다 (다시 시도할 수 있어야 하므로).
        #expect(h.pasteboard.recordedSetString.isEmpty)
        #expect(h.pasteboard.recordedWriteFileURLs.isEmpty)
        #expect(h.vm.multiSelection.count == 2)
    }

    @Test("혼합 붙여넣기 — 자동 붙여넣기 OFF 면 차단, ON 이면 항목 수만큼 연속 합성")
    func mixedPasteRequiresAutoPaste() async {
        let text = ClipFixture.makeText(body: "가")
        let file = ClipFixture.makeFile()

        // 자동 붙여넣기 OFF — 순서를 만들 수단이 없으므로 실행하지 않는다.
        let off = await makeHarness(prefilled: [text, file], autoPaste: false)
        await off.vm.reload()
        off.vm.toggleMultiSelect(id: text.id)
        off.vm.toggleMultiSelect(id: file.id)
        #expect(off.vm.multiPasteBlockReason(for: .paste) == .mixedNeedsAutoPaste)
        await off.vm.runMultiPaste(.paste)
        #expect(off.synthesizer.callCount == 0)
        #expect(off.vm.multiSelection.count == 2)

        // 자동 붙여넣기 ON — 계열별로 모아 [파일 배열 1회 + 텍스트 1회] = 2회.
        let on = await makeHarness(prefilled: [text, file], autoPaste: true)
        await on.vm.reload()
        on.vm.toggleMultiSelect(id: text.id)
        on.vm.toggleMultiSelect(id: file.id)
        #expect(on.vm.multiPasteBlockReason(for: .paste) == nil)
        await on.vm.runMultiPaste(.paste)
        #expect(on.synthesizer.callCount == 2)
        #expect(on.vm.multiSelection.isEmpty)
    }

    /// 사용자 검수에서 드러난 케이스 — `이미지 → 텍스트 → 이미지` 는 예전 구조에서 합성이 3회였고
    /// 마지막 이미지가 누락됐다. 계열별로 모으면 이미지 둘이 **한 배열로 한 번에** 붙어 합성은 2회로 고정된다.
    @Test("혼합 — 이미지·텍스트·이미지: 이미지 둘이 한 배열로 묶여 합성 2회")
    func mixedGroupsImagesIntoSingleArray() async throws {
        let imageA = ClipFixture.makeImage(filePath: "/Library/copies/a.png")
        let text = ClipFixture.makeText(body: "가운데")
        let imageC = ClipFixture.makeImage(filePath: "/Library/copies/c.png")
        let h = await makeHarness(prefilled: [imageA, text, imageC], autoPaste: true)
        await h.vm.reload()

        // 사용자가 고른 순서 그대로 a → 텍스트 → c.
        for id in [imageA.id, text.id, imageC.id] { h.vm.toggleMultiSelect(id: id) }
        await h.vm.runMultiPaste(.paste)

        // 항목 수(3)가 아니라 계열 수(2)만큼만 합성한다.
        #expect(h.synthesizer.callCount == 2)
        // 이미지 둘이 한 번의 파일 배열로, 선택 순서를 지킨 채 붙는다.
        let urls = try #require(h.pasteboard.recordedWriteFileURLs.last)
        #expect(urls.map(\.path) == ["/Library/copies/a.png", "/Library/copies/c.png"])
        // 텍스트는 그 뒤에 한 번.
        #expect(h.pasteboard.recordedSetString.last?.0 == "가운데")
    }

    @Test("혼합 — 텍스트가 여럿이면 연결자로 이어 한 번에 붙는다")
    func mixedJoinsMultipleTexts() async {
        let t1 = ClipFixture.makeText(body: "하나")
        let file = ClipFixture.makeFile()
        let t2 = ClipFixture.makeText(body: "둘")
        let h = await makeHarness(prefilled: [t1, file, t2], autoPaste: true)
        await h.vm.reload()
        UserDefaults.standard.set(", ", forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
        defer { UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.multiPasteSeparator) }

        for id in [t1.id, file.id, t2.id] { h.vm.toggleMultiSelect(id: id) }
        await h.vm.runMultiPaste(.paste)

        #expect(h.synthesizer.callCount == 2)
        #expect(h.pasteboard.recordedSetString.last?.0 == "하나, 둘")
    }

    /// 혼합은 단일 산출물이 없어 새 클립으로 저장하지 않는다.
    @Test("혼합 붙여넣기 — 새 클립을 만들지 않는다")
    func mixedPasteDoesNotRegisterClip() async throws {
        let text = ClipFixture.makeText(body: "가")
        let file = ClipFixture.makeFile()
        let h = await makeHarness(prefilled: [text, file], autoPaste: true)
        await h.vm.reload()
        let before = try await h.repo.fetchAll().count

        h.vm.toggleMultiSelect(id: text.id)
        h.vm.toggleMultiSelect(id: file.id)
        await h.vm.runMultiPaste(.paste)

        #expect(try await h.repo.fetchAll().count == before)
    }

    // MARK: - 실행 흐름 회귀 (사용자 검수 fix-1)

    /// **닫으면서 붙이는 흐름** 회귀 가드.
    ///
    /// `performMultiPasteFlow` 는 popover 를 내린 뒤 붙인다. 그런데 popover 닫힘은 *선택 초기화* 이기도 해서,
    /// 실행 시점에 선택 상태를 다시 읽으면 이미 비어 있고 아무것도 붙지 않는다.
    /// 앞선 테스트들이 `runMultiPaste` 를 직접 불러 이 구간을 건너뛰는 바람에 못 잡았던 결함이라,
    /// 여기서는 흐름 함수 자체를 태우고 `hide` 가 실제로 선택을 비우게 둔다.
    @Test("닫고 붙이는 흐름 — hide 가 선택을 비워도 붙여넣기는 정상 실행")
    func flowPastesEvenThoughHideClearsSelection() async {
        let a = ClipFixture.makeText(body: "A")
        let b = ClipFixture.makeText(body: "B")
        let h = await makeHarness(prefilled: [a, b], autoPaste: true)
        await h.vm.reload()
        h.vm.toggleMultiSelect(id: a.id)
        h.vm.toggleMultiSelect(id: b.id)

        var hideCalled = false
        await PopoverPanel.performMultiPasteFlow(
            viewModel: h.vm,
            action: .paste,
            sourceLabel: "test",
            // 실제 `PopoverWindow.hide()` 와 같이 선택을 비운다.
            hide: {
                hideCalled = true
                h.vm.clearMultiSelection()
            }
        )

        #expect(hideCalled)
        #expect(h.pasteboard.recordedSetString.last?.0 != nil)
        #expect(h.synthesizer.callCount == 1)
    }

    @Test("닫고 복사하는 흐름 — hide 가 선택을 비워도 복사는 정상 실행")
    func flowCopiesEvenThoughHideClearsSelection() async {
        let a = ClipFixture.makeText(body: "A")
        let h = await makeHarness(prefilled: [a])
        await h.vm.reload()
        h.vm.toggleMultiSelect(id: a.id)

        await PopoverPanel.performMultiPasteFlow(
            viewModel: h.vm,
            action: .copy,
            sourceLabel: "test",
            hide: { h.vm.clearMultiSelection() }
        )

        #expect(h.pasteboard.recordedSetString.last?.0 == "A")
        // 복사는 붙여넣기 합성을 하지 않는다.
        #expect(h.synthesizer.callCount == 0)
    }

    /// 유지 모드(자물쇠 ON)에서는 `hide` 자체를 부르지 않는다 — 두 경로가 같은 결과여야 한다.
    @Test("유지 모드 — hide 없이도 같은 결과")
    func flowWorksInKeepOpenMode() async {
        let a = ClipFixture.makeText(body: "A")
        let h = await makeHarness(prefilled: [a])
        await h.vm.reload()
        h.vm.toggleKeepOpenAfterAction()
        h.vm.toggleMultiSelect(id: a.id)

        var hideCalled = false
        await PopoverPanel.performMultiPasteFlow(
            viewModel: h.vm,
            action: .paste,
            sourceLabel: "test",
            hide: { hideCalled = true }
        )

        #expect(hideCalled == false)
        #expect(h.pasteboard.recordedSetString.last?.0 == "A")
    }

    /// 막힌 조합은 popover 를 내리지 않는다 — 닫아버리면 무엇이 막혔는지 볼 화면이 사라진다.
    @Test("혼합 복사 — 흐름에서 popover 를 내리지 않고 선택도 유지")
    func flowDoesNotHideWhenBlocked() async {
        let text = ClipFixture.makeText(body: "가")
        let file = ClipFixture.makeFile()
        let h = await makeHarness(prefilled: [text, file])
        await h.vm.reload()
        h.vm.toggleMultiSelect(id: text.id)
        h.vm.toggleMultiSelect(id: file.id)

        var hideCalled = false
        await PopoverPanel.performMultiPasteFlow(
            viewModel: h.vm,
            action: .copy,
            sourceLabel: "test",
            hide: { hideCalled = true; h.vm.clearMultiSelection() }
        )

        #expect(hideCalled == false)
        #expect(h.vm.multiSelection.count == 2)
        #expect(h.pasteboard.recordedSetString.isEmpty)
    }

    // MARK: - 회귀 (Test Plan #10)

    /// 선택이 비어 있으면 묶음 경로는 아무 일도 하지 않는다 — 기존 단일 동작이 그대로 도는 근거.
    @Test("선택 0개 — 묶음 실행은 무동작")
    func emptySelectionRunsNothing() async {
        let a = ClipFixture.makeText(body: "A")
        let h = await makeHarness(prefilled: [a])
        await h.vm.reload()

        await h.vm.runMultiPaste(.paste)
        await h.vm.runMultiPaste(.copy)

        #expect(h.pasteboard.recordedSetString.isEmpty)
        #expect(h.pasteboard.recordedWriteFileURLs.isEmpty)
        #expect(h.synthesizer.callCount == 0)
    }

    // MARK: - 연결자 조회

    @Test("연결자 원문 — 미설정이면 기본값, 빈 문자열은 유효한 사용자 값")
    func separatorRawFallbackRules() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
        #expect(ClipsViewModel.multiPasteSeparatorRaw == Constants.multiPasteSeparatorDefault)

        // 빈 문자열은 *구분 없이 연결* 이라는 뜻 — 기본값으로 되돌아가면 안 된다.
        UserDefaults.standard.set("", forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
        #expect(ClipsViewModel.multiPasteSeparatorRaw == "")

        UserDefaults.standard.set(", ", forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
        #expect(ClipsViewModel.multiPasteSeparatorRaw == ", ")

        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.multiPasteSeparator)
    }
}
