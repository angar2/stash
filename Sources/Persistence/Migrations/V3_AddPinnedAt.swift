// V3 — `pinned_at` 컬럼 추가 (TASK-019)
// 사유: Pin 사이드바 정렬을 *핀 처리 시점* 기준으로 (최근 핀 우선). last_used_at(paste 시점) / created_at(insert 시점) 으로는 핀 시점과 무관해 사용자 의도 어긋남.
// 기존 핀 row 는 last_used_at 으로 초기화 — NULL 케이스 차단 (첫 실행 시 사이드바 순서가 *기존과 동일*).
import GRDB

enum V3_AddPinnedAt {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_add_pinned_at") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "pinned_at", .datetime)
            }
            // 기존 핀 row 초기화 — last_used_at 값으로 채움.
            try db.execute(sql: """
                UPDATE clips SET pinned_at = last_used_at WHERE is_pinned = 1
            """)
        }
    }
}
