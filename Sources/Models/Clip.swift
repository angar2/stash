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
    /// 핀 표시용 명칭 (TASK-098, V6 마이그레이션). NULL = 미설정 → 값을 그대로 표시.
    /// **표시 전용** — 붙여넣기·복사·검색·중복 판정은 본 값을 참조하지 않는다. 적용 범위는 Pin 사이드바 + 설정 PIN 단축키 행
    /// (일반 히스토리 목록은 값 표시 유지). 클립에 귀속되므로 핀 순서가 바뀌어도 이름이 다른 내용으로 옮겨가지 않는다.
    /// 단 **핀을 해제하면 초기화된다**(`togglePin` 이 NULL 로 되돌림) — 명칭은 핀에만 있는 개념이라 남겨두면
    /// 한참 뒤 재고정 시 잊고 있던 옛 이름이 되살아난다 (TASK-098 검수 정정).
    var pinAlias: String? = nil
    /// 핀 *자리* 번호 1~10 (TASK-098 검수 정정, V7 마이그레이션). NULL = 핀 아님.
    /// **Pin 직접 paste 단축키의 번호가 곧 이 값이다.** 배열 위치로 번호를 계산하던 이전 구조에서는
    /// 앞자리를 해제하면 뒤 항목의 번호와 조합이 전부 밀렸다 — 자리를 데이터로 가져 *해제한 자리만* 비운다.
    /// 중간이 비는 것이 정상 상태다(1·3·4 처럼). 사이드바는 빈 자리를 건너뛰어 나열하되 각 행은 자기 번호를 표시한다.
    var pinSlot: Int? = nil
}

extension Clip {
    /// V4 (TASK-026) — `file_paths_json` 박혀있으면 다중 파일 묶음 클립.
    var isMultiFile: Bool { filePathsJson != nil }

    /// TASK-113 — 원본 파일 접근에 쓰는 security-scoped 북마크들. 다중 파일은 항목 순서대로, 그 외는 `fileBookmark` 하나.
    /// App Store판(샌드박스)만 값이 있고 dmg판은 모두 nil 이다. `SecurityScopedAccess` 가 nil 을 건너뛴다.
    var accessBookmarks: [Data?] {
        if isMultiFile { return (fileEntries ?? []).map(\.bookmark) }
        return [fileBookmark]
    }

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
        case pinAlias = "pin_alias"
        case pinSlot = "pin_slot"
    }
}
