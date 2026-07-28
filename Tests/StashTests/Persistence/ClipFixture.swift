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

    /// 단일 파일 클립 fixture (TASK-099) — `fileOriginalPath` 우선 / 없으면 `filePath` 를 쓰는 경로 규칙 검증용.
    static func makeFile(
        id: UUID = UUID(),
        originalPath: String? = "/tmp/보고서.pdf",
        filePath: String? = "/Library/copies/보고서.pdf",
        lastUsedAt: Date = Date()
    ) -> Clip {
        Clip(
            id: id,
            type: .file,
            body: nil,
            filePath: filePath,
            isFileExternal: originalPath != nil,
            fileOriginalPath: originalPath,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
            createdAt: Date(),
            lastUsedAt: lastUsedAt
        )
    }

    /// 이미지 클립 fixture (TASK-099) — 스크린샷처럼 원본 경로가 없고 보관 카피본만 있는 형태가 기본값.
    static func makeImage(
        id: UUID = UUID(),
        filePath: String? = "/Library/copies/screenshot.png",
        originalPath: String? = nil,
        lastUsedAt: Date = Date()
    ) -> Clip {
        Clip(
            id: id,
            type: .image,
            body: nil,
            filePath: filePath,
            isFileExternal: false,
            fileOriginalPath: originalPath,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: false,
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
