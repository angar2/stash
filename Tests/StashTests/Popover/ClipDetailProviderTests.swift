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

    // (TASK-039) 텍스트 / 이미지 / 단일파일 매칭 검증은 `ClipDetailProvidersTests` 로 이동.
    // 본 파일의 기존 *nil 반환* 케이스 3 종은 본 task 의 Provider 매칭 확장으로 더 이상 유효 X — 케이스 폐기.

    // MARK: - preferredHeight

    @Test("preferredHeight — entries 수에 따라 단조 증가 (TASK-039 — 클램프 제거, raw 추정만)")
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

        // 단조 증가 (raw 추정, 클램프 X — PanelView 가 ScrollView.frame(maxHeight:) 으로 책임)
        #expect(h1 < h3)
        #expect(h3 < h10)
        #expect(h10 < h100)
        // 100개 케이스 = raw 추정값이 clipDetailMaxHeight 초과 (클램프 제거 정합)
        #expect(h100 > DesignTokens.WindowSize.clipDetailMaxHeight)
    }
}
