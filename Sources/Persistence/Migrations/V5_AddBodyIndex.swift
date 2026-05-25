// V5 — `(type, body)` 복합 인덱스 추가 (TASK-082 Phase 8, C5)
// 사유: text 클립 dedup (`WHERE type = ? AND body = ?` exact match) 가 V1 인덱스 (`idx_clips_pinned_last_used`) 무효 → 매 insert 마다 full scan.
// `idx_clips_type_body` 박음 — dedupByEquality 호출이 logN 진입. 200 row 한도 영역에서 진짜 hot path 는 아니지만, 향후 한도 확대 대비 + 인덱스 추가는 안전 연산 (회귀 위험 ↓).
// 검색 (`body LIKE '%query%'`) 은 leading % 라 인덱스 무효 — FTS5 도입은 별도 task 위임.
import GRDB

enum V5_AddBodyIndex {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_add_type_body_index") { db in
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clips_type_body ON clips(type, body)")
        }
    }
}
