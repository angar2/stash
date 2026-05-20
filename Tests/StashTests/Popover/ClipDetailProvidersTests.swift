// 4 Provider 매칭 + preferredHeight + 매칭 우선순위 + commonParentFolder 헬퍼 단위 테스트 (TASK-039)
@testable import stash
import Testing
import Foundation
import CoreGraphics

@Suite("ClipDetailProviders (TASK-039)")
@MainActor
struct ClipDetailProvidersTests {

    // MARK: - Helpers

    private func makeClip(
        type: ClipType,
        body: String? = nil,
        filePath: String? = nil,
        fileOriginalPath: String? = nil,
        filePathsJson: String? = nil
    ) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: type,
            body: body,
            filePath: filePath,
            isFileExternal: false,
            fileOriginalPath: fileOriginalPath,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: now,
            lastUsedAt: now,
            pinnedAt: nil,
            filePathsJson: filePathsJson
        )
    }

    private func sampleEntries(count: Int, baseDir: String = "/tmp") -> [ClipFileEntry] {
        (0..<count).map { i in
            ClipFileEntry(
                originalPath: "\(baseDir)/file-\(i).txt",
                filePath: "/Library/copies/file-\(i).txt",
                isFileExternal: false
            )
        }
    }

    // MARK: - Provider 매칭 (canProvide)

    @Test("텍스트 클립 (body 있음) → TextClipDetailProvider 매칭")
    func textClipMatchesProvider() {
        let clip = makeClip(type: .text, body: "hello world")
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider != nil)
        #expect(provider is TextClipDetailProvider, "TextClipDetailProvider 매칭 기대")
    }

    @Test("텍스트 클립 (body nil 또는 빈 문자열) → Provider 미매칭")
    func textClipEmptyBodyDoesNotMatch() {
        let nilClip = makeClip(type: .text, body: nil)
        #expect(ClipDetailRegistry.provider(for: nilClip) == nil)

        let emptyClip = makeClip(type: .text, body: "")
        #expect(ClipDetailRegistry.provider(for: emptyClip) == nil)
    }

    @Test("이미지 클립 (filePath 있음) → ImageClipDetailProvider 매칭")
    func imageClipMatchesProvider() {
        let clip = makeClip(type: .image, filePath: "/tmp/screenshot.png")
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider != nil)
        #expect(provider is ImageClipDetailProvider, "ImageClipDetailProvider 매칭 기대")
    }

    @Test("이미지 클립 (filePath nil) → Provider 미매칭")
    func imageClipNilFilePathDoesNotMatch() {
        let clip = makeClip(type: .image, filePath: nil)
        #expect(ClipDetailRegistry.provider(for: clip) == nil)
    }

    @Test("단일파일 클립 (filePath 있음, filePathsJson nil) → SingleFileClipDetailProvider 매칭")
    func singleFileClipMatchesProvider() {
        let clip = makeClip(type: .file, filePath: "/tmp/document.pdf", filePathsJson: nil)
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider != nil)
        #expect(provider is SingleFileClipDetailProvider, "SingleFileClipDetailProvider 매칭 기대")
    }

    @Test("단일파일 클립 (filePath nil) → Provider 미매칭")
    func singleFileNilFilePathDoesNotMatch() {
        let clip = makeClip(type: .file, filePath: nil, filePathsJson: nil)
        #expect(ClipDetailRegistry.provider(for: clip) == nil)
    }

    @Test("다중파일 클립 (filePath + filePathsJson 박힘) → MultiFile 우선 매칭 (SingleFile !isMultiFile 가드)")
    func multiFileClipMatchesMultiFileProviderEvenWithFilePathSet() throws {
        let entries = sampleEntries(count: 2)
        let json = try ClipFileEntry.encodeJSON(entries)
        // filePath + filePathsJson 둘 다 박힌 케이스 — MultiFile 우선 매칭 보장
        let clip = makeClip(type: .file, filePath: "/tmp/x.pdf", filePathsJson: json)
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider != nil)
        #expect(provider is MultiFileClipDetailProvider, "MultiFile 우선 매칭 기대 (배열 first match + SingleFile !isMultiFile 가드)")
    }

    @Test("다중파일 클립 (TASK-027 회귀 차단) — MultiFileClipDetailProvider 매칭 유지")
    func multiFileClipStillMatchesMultiFileProvider() throws {
        let entries = sampleEntries(count: 3)
        let json = try ClipFileEntry.encodeJSON(entries)
        let clip = makeClip(type: .file, filePathsJson: json)
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider is MultiFileClipDetailProvider)
    }

    // MARK: - preferredHeight (raw 추정, 클램프 X)

    @Test("Text preferredHeight — body 라인 수 단조 증가 (본문 자체 height, padding/클램프 X — TASK-039 fix2)")
    func textPreferredHeightMonotonicWithLines() {
        let provider = TextClipDetailProvider()
        let h1   = provider.preferredHeight(for: makeClip(type: .text, body: "1줄"))
        let h10  = provider.preferredHeight(for: makeClip(type: .text, body: Array(repeating: "line", count: 10).joined(separator: "\n")))
        let h50  = provider.preferredHeight(for: makeClip(type: .text, body: Array(repeating: "line", count: 50).joined(separator: "\n")))
        let h200 = provider.preferredHeight(for: makeClip(type: .text, body: Array(repeating: "line", count: 200).joined(separator: "\n")))

        #expect(h1 < h10)
        #expect(h10 < h50)
        #expect(h50 < h200)
        // 본문 자체 height (lines × lineHeight) — padding 가산 X. 200줄 = raw 추정값이 clipDetailMaxHeight 초과 (클램프 X)
        #expect(h200 > DesignTokens.WindowSize.clipDetailMaxHeight)
    }

    @Test("Image preferredHeight — NSImage 로드 실패 시 16:10 fallback aspectRatio (본문 자체 height only — TASK-039 fix2)")
    func imagePreferredHeightAspectRatioFallback() {
        let provider = ImageClipDetailProvider()
        let clip = makeClip(type: .image, filePath: "/nonexistent/path/missing.png")
        let h = provider.preferredHeight(for: clip)
        // 본문 자체 height = (clipDetailWidth - 2 × padding) × (10/16) — padding 가산 X (PanelView 책임)
        let imageW = DesignTokens.WindowSize.clipDetailWidth
            - 2 * DesignTokens.Spacing.clipDetailPadding
        let expected = imageW * (10.0 / 16.0)
        #expect(abs(h - expected) < 0.5, "16:10 fallback + 본문 자체 height (padding X) 기대. 실제=\(h) / 기대=\(expected)")
    }

    @Test("SingleFile preferredHeight — 본문 자체 height = clipDetailRowHeight (padding X — TASK-039 fix2)")
    func singleFilePreferredHeightStable() {
        let provider = SingleFileClipDetailProvider()
        let h = provider.preferredHeight(for: makeClip(type: .file, filePath: "/tmp/a.pdf"))
        let expected = DesignTokens.Spacing.clipDetailRowHeight
        #expect(abs(h - expected) < 0.5, "본문 자체 height = rowHeight 기대 (padding 가산 X). 실제=\(h) / 기대=\(expected)")
    }

    // MARK: - commonParentFolder 헬퍼

    @Test("commonParentFolder — entries 모두 동일 폴더 → 폴더 경로 반환")
    func commonParentFolderSamePath() {
        let entries = sampleEntries(count: 3, baseDir: "/Users/zeke/Documents/Q1")
        let result = commonParentFolder(entries)
        #expect(result == "/Users/zeke/Documents/Q1")
    }

    @Test("commonParentFolder — entries 폴더 혼재 → nil 반환 (여러 폴더 fallback 트리거)")
    func commonParentFolderMultiFolder() {
        let entries = [
            ClipFileEntry(originalPath: "/Users/zeke/Documents/a.pdf", filePath: "/cp/a.pdf", isFileExternal: false),
            ClipFileEntry(originalPath: "/Users/zeke/Desktop/b.png", filePath: "/cp/b.png", isFileExternal: false)
        ]
        let result = commonParentFolder(entries)
        #expect(result == nil)
    }

    @Test("commonParentFolder — 빈 entries → nil 반환")
    func commonParentFolderEmpty() {
        let result = commonParentFolder([])
        #expect(result == nil)
    }
}
