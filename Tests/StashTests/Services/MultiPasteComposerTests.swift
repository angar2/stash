// 다중 선택 붙여넣기 — 순수 계층 단위 테스트 (TASK-099, Test Plan #1~#5)
//
// **본 스위트 통과 = 기능 동작 아님.** 페이스트보드 쓰기 · ⌘V 합성 · 프리뷰 바 표시는
// 단위 테스트로 검증할 수 없다 (task Test Plan #11~#21 실기 검수가 유일한 근거).
// 여기서 지키는 것은 *계열 판정 · 연결자 해석 · 선택 순서 연결 · 프리뷰 구성 · 파일 URL 수집* 뿐이다.
import Testing
import Foundation
@testable import stash

@Suite("다중 선택 붙여넣기 순수 계층 (TASK-099)")
struct MultiPasteComposerTests {

    // MARK: - 연결 순서 (Test Plan #1)

    /// 연결 순서는 목록 나열 순서가 아니라 **선택한 순서** 다. Composer 는 입력 배열을 재정렬하지 않는다.
    @Test("join 은 입력 배열 순서(=선택 순서) 그대로")
    func joinFollowsSelectionOrder() {
        // 목록 순서는 가·나·다·라 이지만 선택은 1→3→4→2 (가·다·라·나) 로 했다.
        let 가 = ClipFixture.makeText(body: "가")
        let 나 = ClipFixture.makeText(body: "나")
        let 다 = ClipFixture.makeText(body: "다")
        let 라 = ClipFixture.makeText(body: "라")
        let selected = [가, 다, 라, 나]

        let separator = MultiPasteComposer.resolveSeparator(", ")
        #expect(MultiPasteComposer.joinedText(clips: selected, separator: separator) == "가, 다, 라, 나")
    }

    // MARK: - 연결자 해석 (Test Plan #2·#3)

    @Test("연결자 escape 표기 — \\n 은 개행 1자, \\t 는 탭 1자")
    func separatorEscapeResolved() {
        let newline = MultiPasteComposer.resolveSeparator("\\n")
        #expect(newline == "\n")
        #expect(newline.count == 1)

        let tab = MultiPasteComposer.resolveSeparator("\\t")
        #expect(tab == "\t")
        #expect(tab.count == 1)

        let a = ClipFixture.makeText(body: "A")
        let b = ClipFixture.makeText(body: "B")
        #expect(MultiPasteComposer.joinedText(clips: [a, b], separator: newline) == "A\nB")
        #expect(MultiPasteComposer.joinedText(clips: [a, b], separator: tab) == "A\tB")
    }

    @Test("연결자 원문에 escape 표기가 없으면 그대로 통과")
    func separatorPlainPassthrough() {
        #expect(MultiPasteComposer.resolveSeparator(", ") == ", ")
        #expect(MultiPasteComposer.resolveSeparator(" ") == " ")
        #expect(MultiPasteComposer.resolveSeparator("—") == "—")
    }

    @Test("빈 연결자 = 구분 없이 연결")
    func emptySeparatorJoinsDirectly() {
        let clips = ["A", "B", "C"].map { ClipFixture.makeText(body: $0) }
        let separator = MultiPasteComposer.resolveSeparator("")
        #expect(separator.isEmpty)
        #expect(MultiPasteComposer.joinedText(clips: clips, separator: separator) == "ABC")
    }

    /// 줄바꿈·탭이 기본값이라, 프리뷰에서 보이지 않으면 무엇으로 이어지는지 확인할 수 없다.
    @Test("연결자 시각 표기 — 보이지 않는 문자를 기호로")
    func separatorDisplayGlyphs() {
        #expect(MultiPasteComposer.separatorDisplay("\\n") == "⏎")
        #expect(MultiPasteComposer.separatorDisplay("\\t") == "⇥")
        #expect(MultiPasteComposer.separatorDisplay(", ") == ", ")
        #expect(MultiPasteComposer.separatorDisplay("") == "")
    }

    // MARK: - 계열 판정 (Test Plan #4)

    @Test("계열 판정 — 텍스트만 / 파일·이미지만 / 혼합")
    func categoryBranches() {
        let text1 = ClipFixture.makeText(body: "가")
        let text2 = ClipFixture.makeText(body: "나")
        let file = ClipFixture.makeFile()
        let image = ClipFixture.makeImage()
        let multi = ClipFixture.makeMultiFile()

        #expect(MultiPasteComposer.category(of: [text1, text2]) == .text)
        #expect(MultiPasteComposer.category(of: [file, image, multi]) == .files)
        #expect(MultiPasteComposer.category(of: [text1, file]) == .mixed)
        #expect(MultiPasteComposer.category(of: [image, text2]) == .mixed)
    }

    /// 빈 선택은 묶음 실행 대상이 아니다 — 이 nil 이 곧 *기존 단일 동작 유지* 분기의 근거다.
    @Test("빈 선택은 계열 없음(nil)")
    func emptySelectionHasNoCategory() {
        #expect(MultiPasteComposer.category(of: []) == nil)
        #expect(MultiPasteComposer.preview(clips: [], separatorRaw: "\\n") == nil)
    }

    // MARK: - 파일 수집

    @Test("파일 URL 수집 — 선택 순서 유지 + 다중 파일 클립은 항목 단위로 펼침")
    func fileURLsExpandMultiFileInOrder() {
        let file = ClipFixture.makeFile(originalPath: "/tmp/보고서.pdf", filePath: "/Library/copies/보고서.pdf")
        let multi = ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/copies/a.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/copies/b.png", isFileExternal: false)
        ])

        let urls = MultiPasteComposer.fileURLs(clips: [file, multi])
        #expect(urls.map(\.path) == ["/tmp/보고서.pdf", "/tmp/a.txt", "/tmp/b.png"])
    }

    /// 경로 우선순위는 단일 클립 붙여넣기와 같아야 한다 — 원본이 있으면 원본, 없으면 보관 카피본.
    @Test("경로 우선순위 — 원본 우선, 없으면 보관 카피본")
    func filePathPrecedence() {
        let withOriginal = ClipFixture.makeFile(originalPath: "/tmp/원본.pdf", filePath: "/Library/copies/사본.pdf")
        #expect(MultiPasteComposer.filePaths(of: withOriginal) == ["/tmp/원본.pdf"])

        let copyOnly = ClipFixture.makeImage(filePath: "/Library/copies/screenshot.png", originalPath: nil)
        #expect(MultiPasteComposer.filePaths(of: copyOnly) == ["/Library/copies/screenshot.png"])

        // 텍스트 클립은 파일이 없다 — 혼합 계열에서 텍스트가 파일 배열에 섞여 들어가면 안 된다.
        #expect(MultiPasteComposer.filePaths(of: ClipFixture.makeText(body: "가")).isEmpty)
    }

    // MARK: - 프리뷰 (Test Plan #5)

    @Test("텍스트 프리뷰 — 선택 순서 조각 + 연결자 시각 표기")
    func textPreview() throws {
        let clips = ["지크님 안녕하세요", "계좌번호 110-123-456789", "감사합니다"].map { ClipFixture.makeText(body: $0) }
        let preview = try #require(MultiPasteComposer.preview(clips: clips, separatorRaw: "\\n"))

        #expect(preview.category == .text)
        #expect(preview.selectionCount == 3)
        #expect(preview.mode == .textJoin)
        #expect(preview.segmentTexts == ["지크님 안녕하세요", "계좌번호 110-123-456789", "감사합니다"])
        #expect(preview.segments.allSatisfy { $0.kind == .text })
        // 구분 표기는 칩 *사이* 에만 놓인다 — 조각이 3개면 2개.
        #expect(preview.separators == ["⏎", "⏎"])
        #expect(preview.body == "지크님 안녕하세요⏎계좌번호 110-123-456789⏎감사합니다")
    }

    @Test("파일 프리뷰 — 파일명이 선택 순서로 나열 + 실제 붙는 파일 개수")
    func filePreviewListsNamesWithCount() throws {
        // 단일 파일 1개 + 다중 파일 묶음 1개 = 클립 2개, 실제 파일 3개.
        let file = ClipFixture.makeFile(originalPath: "/tmp/보고서.pdf", filePath: "/Library/copies/보고서.pdf")
        let multi = ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/copies/a.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/copies/b.png", isFileExternal: false)
        ])
        let preview = try #require(MultiPasteComposer.preview(clips: [file, multi], separatorRaw: "\\n"))

        #expect(preview.category == .files)
        #expect(preview.selectionCount == 2)
        // 선택 개수(2)가 아니라 *실제로 붙는 파일 개수*(3) 를 말해야 한다.
        #expect(preview.mode == .fileBundle(fileCount: 3))
        #expect(preview.segmentTexts == ["보고서.pdf", "a.txt", "b.png"])
        // 파일은 배열 하나로 한 번에 붙는다 — 이어붙이는 개념이 아니라 구분 표기를 두지 않는다.
        #expect(preview.separators == ["", ""])
        // 파일 조각은 파일 계열로 표시돼야 한다 (화면이 회색 칩으로 그리는 근거).
        #expect(preview.segments.allSatisfy { $0.kind == .file })
    }

    // MARK: - 혼합 실행 순서 (사용자 검수 fix-2)

    /// 사용자 검수에서 드러난 케이스 — `이미지 → 텍스트 → 이미지` 로 고르면 마지막 이미지가 누락됐다.
    /// 계열이 번갈아 나오면 항목 수만큼 합성해야 해서 뒤쪽이 잘 떨어진다.
    /// 계열별로 모으면 [파일 배열 1회 + 텍스트 1회] = **합성 2회 고정** 이 된다.
    @Test("혼합 실행 순서 — 파일·이미지를 앞으로, 각 묶음 안에서는 선택 순서 유지")
    func sequentialGroupsPutFilesFirst() {
        let imageA = ClipFixture.makeImage(filePath: "/Library/copies/a.png")
        let text = ClipFixture.makeText(body: "가운데 텍스트")
        let imageC = ClipFixture.makeImage(filePath: "/Library/copies/c.png")

        let groups = MultiPasteComposer.sequentialGroups(clips: [imageA, text, imageC])
        #expect(groups.files.map { $0.filePath } == ["/Library/copies/a.png", "/Library/copies/c.png"])
        #expect(groups.texts.map { $0.body } == ["가운데 텍스트"])

        // 두 이미지가 한 배열로 묶여 *한 번* 에 붙는다.
        #expect(MultiPasteComposer.fileURLs(clips: groups.files).map(\.path)
                == ["/Library/copies/a.png", "/Library/copies/c.png"])
    }

    @Test("혼합 실행 순서 — 텍스트 여럿도 각자 순서를 지킨 채 뒤로 모인다")
    func sequentialGroupsKeepTextOrder() {
        let t1 = ClipFixture.makeText(body: "하나")
        let file = ClipFixture.makeFile()
        let t2 = ClipFixture.makeText(body: "둘")

        let groups = MultiPasteComposer.sequentialGroups(clips: [t1, file, t2])
        #expect(groups.files.count == 1)
        #expect(groups.texts.map { $0.body } == ["하나", "둘"])
    }

    /// 프리뷰는 **실제 실행 순서** 를 보여야 한다 — 선택 순서 그대로 그리면 화면과 결과가 어긋난다.
    @Test("혼합 프리뷰 — 실행 순서(파일 먼저)로 나열 + 텍스트는 한 덩어리")
    func mixedPreviewFollowsExecutionOrder() throws {
        let text = ClipFixture.makeText(body: "지크님 안녕하세요")
        let image = ClipFixture.makeImage(filePath: "/Library/copies/screenshot.png")
        let tail = ClipFixture.makeText(body: "감사합니다")
        let preview = try #require(MultiPasteComposer.preview(clips: [text, image, tail], separatorRaw: "\\n"))

        #expect(preview.category == .mixed)
        #expect(preview.selectionCount == 3)
        // 혼합 라벨은 *파일 개수* 를 말한다 — 텍스트는 이어져 한 덩어리로 붙으므로 셀 것이 없다.
        #expect(preview.mode == .sequential(fileCount: 1))
        // 이미지가 앞으로 오고, 텍스트는 각자 칩으로 남는다 (칩 사이에 연결자).
        #expect(preview.segmentTexts == ["screenshot.png", "지크님 안녕하세요", "감사합니다"])
        // 파일 묶음 ↔ 텍스트 경계에는 화살표, 텍스트끼리는 연결자.
        #expect(preview.separators == ["→", "⏎"])
        // 계열이 조각마다 붙어 있어야 화면이 색을 가를 수 있다 (파일=회색 / 텍스트=강조).
        #expect(preview.segments.map(\.kind) == [.file, .text, .text])
        #expect(preview.body == "screenshot.png→지크님 안녕하세요⏎감사합니다")
    }

    /// 연결자를 바꾸면 프리뷰가 즉시 따라와야 한다 (설정 → 프리뷰 반영 경로의 순수 계층 근거).
    @Test("연결자 변경이 프리뷰에 반영")
    func previewFollowsSeparatorChange() throws {
        let clips = ["가", "나"].map { ClipFixture.makeText(body: $0) }
        #expect(try #require(MultiPasteComposer.preview(clips: clips, separatorRaw: ", ")).separators == [", "])
        #expect(try #require(MultiPasteComposer.preview(clips: clips, separatorRaw: ", ")).body == "가, 나")
        // 연결자를 비우면 구분 표기도 비어 칩이 바로 붙는다 (= 구분 없이 연결).
        #expect(try #require(MultiPasteComposer.preview(clips: clips, separatorRaw: "")).separators == [""])
        #expect(try #require(MultiPasteComposer.preview(clips: clips, separatorRaw: "")).body == "가나")
    }
}
