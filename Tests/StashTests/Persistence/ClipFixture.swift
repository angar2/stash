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
}
