// 테스트 전용 Clip 팩토리 헬퍼 — 각 테스트에서 Clip 생성 보일러플레이트 제거
@testable import stash
import Foundation

enum ClipFixture {
    static func makeText(
        id: UUID = UUID(),
        body: String = "test clip",
        isPinned: Bool = false,
        lastUsedAt: Date = Date()
    ) -> Clip {
        Clip(
            id: id,
            type: .text,
            body: body,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: isPinned,
            createdAt: Date(),
            lastUsedAt: lastUsedAt
        )
    }

    /// 다중 파일 클립 fixture (TASK-026) — entries 배열을 JSON 직렬화해 filePathsJson 박음. file_path / fileOriginalPath / isFileExternal 컬럼 상호 배타.
    static func makeMultiFile(
        id: UUID = UUID(),
        entries: [ClipFileEntry] = [
            ClipFileEntry(originalPath: "/tmp/a.txt", filePath: "/Library/copies/a.txt", isFileExternal: false),
            ClipFileEntry(originalPath: "/tmp/b.png", filePath: "/Library/copies/b.png", isFileExternal: false)
        ],
        isPinned: Bool = false,
        lastUsedAt: Date = Date()
    ) -> Clip {
        let json = (try? ClipFileEntry.encodeJSON(entries)) ?? "[]"
        return Clip(
            id: id,
            type: .file,
            body: nil,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: isPinned,
            createdAt: Date(),
            lastUsedAt: lastUsedAt,
            pinnedAt: nil,
            filePathsJson: json
        )
    }
}
