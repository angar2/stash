// 클립보드 항목 도메인 모델 — Clip 엔티티 (DATA-MODEL §1 정합)
import Foundation
import GRDB

struct Clip: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let type: ClipType
    let body: String?
    let filePath: String?
    let isFileExternal: Bool
    let fileOriginalPath: String?
    let fileBookmark: Data?
    let sourceAppBundleId: String?
    var isPinned: Bool
    let createdAt: Date
    var lastUsedAt: Date
    /// 핀 처리 시점 (TASK-019) — `isPinned=false → true` 시 `Date()` 박힘 / `true → false` 시 `nil`. Pin 사이드바 정렬 기준 (최근 핀 우선). 기존 init 호출 사이트 영향 X — 기본값 nil.
    var pinnedAt: Date? = nil
    /// 다중 파일 묶음 — `ClipFileEntry` 배열 JSON 직렬화 (TASK-026, V4 마이그레이션). 단일 파일·텍스트·이미지는 NULL.
    /// 컬럼 상호 배타: 다중 파일 시 `file_path` / `file_original_path` 모두 NULL / `is_file_external` 0.
    var filePathsJson: String? = nil
}

extension Clip {
    /// V4 (TASK-026) — `file_paths_json` 박혀있으면 다중 파일 묶음 클립.
    var isMultiFile: Bool { filePathsJson != nil }

    /// V4 (TASK-026) — JSON 디코드. 매 호출 디코드 (캐시 X), 실패 시 nil. 비용 무시 (200 row × μs).
    var fileEntries: [ClipFileEntry]? {
        guard let json = filePathsJson else { return nil }
        return ClipFileEntry.decodeJSON(json)
    }
}

extension Clip: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clips"

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case body
        case filePath = "file_path"
        case isFileExternal = "is_file_external"
        case fileOriginalPath = "file_original_path"
        case fileBookmark = "file_bookmark"
        case sourceAppBundleId = "source_app_bundle_id"
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case pinnedAt = "pinned_at"
        case filePathsJson = "file_paths_json"
    }
}
