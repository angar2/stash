// 파일 클립 북마크 저장·복원·중복 판정과 원본 접근 열기·닫기 정책 단위 테스트 (TASK-113)
import Testing
import Foundation
@testable import stash

@Suite("SecurityScopedBookmarkStorage")
struct SecurityScopedBookmarkStorageTests {

    /// TASK-113 이전 dmg판이 저장하던 묶음 JSON 그대로 — `bookmark` 키가 없다.
    private static let legacyMultiFileJSON =
        #"[{"file_path":"\/Library\/copies\/a.txt","is_file_external":false,"original_path":"\/tmp\/a.txt"},"#
        + #"{"file_path":"\/tmp\/big.mov","is_file_external":true,"original_path":"\/tmp\/big.mov"}]"#

    private func makeRepo() throws -> (GRDBClipRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stash-bookmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let repo = try GRDBClipRepository(dbPath: tempDir.appendingPathComponent("test.db"), historyLimit: { 200 })
        return (repo, tempDir)
    }

    // MARK: - 기존 dmg판 데이터 호환

    @Test("북마크 없는 항목은 JSON 이 이전과 같다 — dmg판 저장값 불변")
    func entryWithoutBookmarkEncodesLikeBefore() throws {
        let entries = [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/copies/a.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/big.mov", filePath: "/tmp/big.mov", isFileExternal: true)
        ]
        #expect(try ClipFileEntry.encodeJSON(entries) == Self.legacyMultiFileJSON)
    }

    @Test("기존 dmg판 데이터 — 북마크 없는 단일·묶음 파일 클립이 그대로 읽히고 붙여넣기 경로도 같다")
    func legacyClipsReadUnchanged() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        var legacyMulti = ClipFixture.makeMultiFile()
        legacyMulti.filePathsJson = Self.legacyMultiFileJSON
        let legacySingle = ClipFixture.makeFile(originalPath: "/tmp/보고서.pdf", filePath: "/Library/copies/보고서.pdf")
        _ = try await repo.insert(legacyMulti)
        _ = try await repo.insert(legacySingle)

        let all = try await repo.fetchAll()
        #expect(all.count == 2)
        let multi = try #require(all.first { $0.id == legacyMulti.id })
        let single = try #require(all.first { $0.id == legacySingle.id })
        #expect(multi.filePathsJson == Self.legacyMultiFileJSON)
        #expect(multi.fileEntries?.map(\.bookmark) == [nil, nil])
        #expect(multi.accessBookmarks == [nil, nil])
        #expect(single.accessBookmarks == [nil])
        #expect(MultiPasteComposer.filePaths(of: multi) == ["/tmp/a.txt", "/tmp/big.mov"])
        #expect(MultiPasteComposer.filePaths(of: single) == ["/tmp/보고서.pdf"])
    }

    // MARK: - 저장·복원과 중복 판정

    @Test("북마크가 담긴 단일·묶음 파일 클립을 저장하고 다시 읽으면 북마크가 그대로 돌아온다")
    func bookmarksRoundTrip() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let single = Clip(
            id: UUID(), type: .file, body: nil,
            filePath: "/Library/copies/x.pdf", isFileExternal: false,
            fileOriginalPath: "/tmp/x.pdf", fileBookmark: Data([1, 2, 3]),
            sourceAppBundleId: nil, isPinned: false, createdAt: Date(), lastUsedAt: Date()
        )
        let multi = ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/copies/a.txt", isFileExternal: false, bookmark: Data([4])),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/copies/b.png", isFileExternal: false, bookmark: nil)
        ])
        _ = try await repo.insert(single)
        _ = try await repo.insert(multi)

        let all = try await repo.fetchAll()
        #expect(all.first { $0.id == single.id }?.accessBookmarks == [Data([1, 2, 3])])
        #expect(all.first { $0.id == multi.id }?.accessBookmarks == [Data([4]), nil])
    }

    @Test("같은 파일 묶음을 북마크만 다르게 다시 복사하면 새 줄 없이 기존 클립이 맨 위로 올라온다")
    func multiFileDedupIgnoresBookmark() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        func bundle(_ mark: UInt8, at date: Date) -> Clip {
            ClipFixture.makeMultiFile(entries: [
                ClipFileEntry(originalPath: "/tmp/big1.mov", filePath: "/tmp/big1.mov", isFileExternal: true, bookmark: Data([mark])),
                ClipFileEntry(originalPath: "/tmp/big2.mov", filePath: "/tmp/big2.mov", isFileExternal: true, bookmark: Data([mark, mark]))
            ], lastUsedAt: date)
        }
        let first = bundle(1, at: Date(timeIntervalSince1970: 1_000))
        _ = try await repo.insert(first)
        _ = try await repo.insert(ClipFixture.makeText(body: "중간", lastUsedAt: Date(timeIntervalSince1970: 2_000)))
        _ = try await repo.insert(bundle(9, at: Date(timeIntervalSince1970: 3_000)))

        let all = try await repo.fetchAll()
        #expect(all.count == 2)
        #expect(all.first?.id == first.id)
    }

    @Test("항목이 다른 묶음은 북마크가 같아도 따로 쌓인다")
    func multiFileDifferentEntriesNotDeduped() async throws {
        let (repo, dir) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await repo.insert(ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a", filePath: "/tmp/a", isFileExternal: true, bookmark: Data([1])),
            ClipFileEntry(originalPath: "/tmp/b", filePath: "/tmp/b", isFileExternal: true, bookmark: Data([1]))
        ]))
        _ = try await repo.insert(ClipFixture.makeMultiFile(entries: [
            ClipFileEntry(originalPath: "/tmp/a", filePath: "/tmp/a", isFileExternal: true, bookmark: Data([1])),
            ClipFileEntry(originalPath: "/tmp/c", filePath: "/tmp/c", isFileExternal: true, bookmark: Data([1]))
        ]))
        #expect(try await repo.fetchAll().count == 2)
    }

    // MARK: - 원본 접근 열기·닫기 정책

    @Test("미리보기(읽기)는 끝나자마자 닫힌다")
    func readAccessClosesImmediately() {
        let opener = CountingOpener()
        let access = SecurityScopedAccess(opener: opener)
        let seenOpen = access.withAccess([Data([1]), nil, Data([2])]) { opener.openCount }
        #expect(seenOpen == 2)          // nil 북마크는 건너뛴다
        #expect(opener.openCount == 0)  // body 가 끝나면 모두 닫힌다
        #expect(access.heldCount == 0)
    }

    @Test("붙여넣기는 다음 붙여넣기 때 앞의 것이 닫혀 마지막 한 건분만 열려 있다")
    func pasteHoldsUntilNextPaste() {
        let opener = CountingOpener()
        let access = SecurityScopedAccess(opener: opener)
        access.hold([Data([1]), Data([2]), Data([3])])
        #expect(opener.openCount == 3)
        access.hold([Data([4])])
        #expect(opener.openCount == 1)
        #expect(access.heldCount == 1)
        access.hold([nil])  // 북마크 없는 클립(텍스트·dmg판)을 붙여넣어도 앞의 것은 닫힌다
        #expect(opener.openCount == 0)
    }

    @Test("판정 규칙 — 실행 중 반영되는 값 또는 재실행 뒤 갱신되는 값 중 하나라도 허용이면 허용")
    func permissionDecision() {
        #expect(SandboxPermissionDecision.isGranted(axTrusted: true, postEventPreflight: false))
        #expect(SandboxPermissionDecision.isGranted(axTrusted: false, postEventPreflight: true))
        #expect(!SandboxPermissionDecision.isGranted(axTrusted: false, postEventPreflight: false))
    }

    @Test("dmg판(테스트 빌드)은 북마크를 만들지 않는다")
    func dmgBuildMakesNoBookmark() {
        #expect(SecurityScopedAccess.makeBookmark(for: URL(fileURLWithPath: NSTemporaryDirectory())) == nil)
    }
}

/// 열린 자원 수를 세는 가짜 창구.
private final class CountingOpener: ScopedResourceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]

    var openCount: Int {
        lock.lock(); defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }

    func open(_ bookmark: Data) -> URL? {
        let url = URL(fileURLWithPath: "/fake/\(bookmark.map(String.init).joined(separator: "-"))")
        lock.lock(); counts[url, default: 0] += 1; lock.unlock()
        return url
    }

    func close(_ url: URL) {
        lock.lock(); counts[url, default: 0] -= 1; lock.unlock()
    }
}
