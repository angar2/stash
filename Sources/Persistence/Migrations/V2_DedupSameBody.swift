// V2 — 동일 (type, body) 텍스트 클립 dedup 마이그레이션 (TASK-019 fix 5차)
// 사유: ClipboardWatcher 의 paste 후 자동 감지로 누적된 동일 body 클립 정리. 그룹별로 핀 우선 + 최신 1개 보존, 나머지 삭제.
// image / file 클립은 dedup 안 함 (file_path 가 매번 다른 UUID 파일명이라 자연 중복 X).
import GRDB

enum V2_DedupSameBody {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_dedup_same_body") { db in
            // (type='text', body) 그룹별 ROW_NUMBER 매기고 rn > 1 인 row 삭제.
            // 순위 기준: is_pinned DESC (핀 우선) → last_used_at DESC (최신) → id ASC (tie-break, 결정적).
            try db.execute(sql: """
                DELETE FROM clips WHERE id IN (
                    SELECT id FROM (
                        SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY type, body
                            ORDER BY is_pinned DESC, last_used_at DESC, id ASC
                        ) AS rn
                        FROM clips
                        WHERE type = 'text' AND body IS NOT NULL
                    )
                    WHERE rn > 1
                )
            """)
        }
    }
}
