// ClipDetailRegistry + MultiFileClipDetailProvider 매칭 + preferredHeight 단위 테스트 (TASK-027)
@testable import stash
import Testing
import Foundation
import CoreGraphics

@Suite("ClipDetailProvider")
@MainActor
struct ClipDetailProviderTests {

    // MARK: - Helpers

    private func makeClip(
        type: ClipType,
        filePath: String? = nil,
        filePathsJson: String? = nil
    ) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: type,
            body: nil,
            filePath: filePath,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: now,
            lastUsedAt: now,
            pinnedAt: nil,
            filePathsJson: filePathsJson
        )
    }

    private func makeMultiFileClip(entries: [ClipFileEntry]) throws -> Clip {
        let json = try ClipFileEntry.encodeJSON(entries)
        return makeClip(type: .file, filePathsJson: json)
    }

    private func sampleEntries(count: Int) -> [ClipFileEntry] {
        (0..<count).map { i in
            ClipFileEntry(
                originalPath: "/tmp/file-\(i).txt",
                filePath: "/Library/copies/file-\(i).txt",
                isFileExternal: false
            )
        }
    }

    // MARK: - Provider matching

    @Test("다중파일 클립 (entries 2개) — Provider 매칭")
    func multiFileClipMatchesProvider() throws {
        let clip = try makeMultiFileClip(entries: sampleEntries(count: 2))
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider != nil)
    }

    @Test("다중파일 클립 (빈 entries) — Provider 미매칭 (canProvide false)")
    func multiFileClipEmptyEntriesDoesNotMatch() throws {
        let clip = try makeMultiFileClip(entries: [])
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider == nil)
    }

    @Test("다중파일 클립 (잘못된 JSON) — fileEntries decode 실패 → Provider 미매칭")
    func multiFileClipMalformedJsonDoesNotMatch() {
        let clip = makeClip(type: .file, filePathsJson: "not-a-json")
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider == nil)
    }

    @Test("텍스트 클립 — Provider 미매칭")
    func textClipReturnsNilProvider() {
        let clip = makeClip(type: .text, filePath: nil, filePathsJson: nil)
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider == nil)
    }

    @Test("이미지 클립 — Provider 미매칭")
    func imageClipReturnsNilProvider() {
        let clip = makeClip(type: .image, filePath: "/tmp/screenshot.png", filePathsJson: nil)
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider == nil)
    }

    @Test("단일 파일 클립 (filePathsJson nil) — Provider 미매칭")
    func singleFileClipReturnsNilProvider() {
        let clip = makeClip(type: .file, filePath: "/tmp/document.pdf", filePathsJson: nil)
        let provider = ClipDetailRegistry.provider(for: clip)
        #expect(provider == nil)
    }

    // MARK: - preferredHeight

    @Test("preferredHeight — entries 수에 따라 단조 증가 후 clipDetailMaxHeight 상한 클램프")
    func preferredHeightMonotonicWithFileCount() throws {
        let provider = MultiFileClipDetailProvider()
        let clip1  = try makeMultiFileClip(entries: sampleEntries(count: 1))
        let clip3  = try makeMultiFileClip(entries: sampleEntries(count: 3))
        let clip10 = try makeMultiFileClip(entries: sampleEntries(count: 10))
        let clip100 = try makeMultiFileClip(entries: sampleEntries(count: 100))

        let h1 = provider.preferredHeight(for: clip1)
        let h3 = provider.preferredHeight(for: clip3)
        let h10 = provider.preferredHeight(for: clip10)
        let h100 = provider.preferredHeight(for: clip100)

        // 단조 증가
        #expect(h1 < h3)
        #expect(h3 < h10)
        // 100개는 maxHeight 상한 클램프
        #expect(h100 == DesignTokens.WindowSize.clipDetailMaxHeight)
        // 모든 값 <= maxHeight
        #expect(h1 <= DesignTokens.WindowSize.clipDetailMaxHeight)
        #expect(h10 <= DesignTokens.WindowSize.clipDetailMaxHeight)
    }
}
