// V7 — `pin_slot` 컬럼 추가 (TASK-098 검수 정정)
//
// 사유: Pin 직접 paste 단축키의 *번호* 를 `pinnedClips` **배열 위치**(핀한 시각 순서)로 계산하고 있었다.
// 그래서 2번을 핀 해제하면 3번이 2번으로 당겨지고 조합까지 `⌥⌘3` → `⌥⌘2` 로 바뀌었다 —
// 조합을 외워서 누르는 기능의 전제가 무너지는 결함. 자리(1~10)를 데이터로 갖게 해 *해제한 자리만* 비운다.
//
// 백필: 기존 핀 row 에 *지금 보이는 순서* (`pinned_at` 오름차순, NULL 은 `created_at`) 그대로 1..N 을 배정한다.
// → 업데이트 직후 사용자의 조합이 가리키는 대상이 바뀌지 않는다.
//
// 구현 주의: 백필을 **순수 SQL** 로 한다. 마이그레이션 안에서 `Clip` 레코드 타입을 쓰면 이후 Vn 이 컬럼을 추가할 때
// *그 시점 스키마에 없는 컬럼* 을 디코드하려다 깨진다(마이그레이션 고정 시점 원칙).
import GRDB

enum V7_AddPinSlot {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_add_pin_slot") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "pin_slot", .integer)
            }
            // ROW_NUMBER 로 표시 순서를 그대로 자리 번호로. 상한(10)을 넘는 row 는 NULL 로 남긴다
            // (togglePin 가드상 발생 X — 손상 DB 방어).
            try db.execute(sql: """
                WITH ordered AS (
                    SELECT id, ROW_NUMBER() OVER (ORDER BY COALESCE(pinned_at, created_at) ASC) AS rn
                    FROM clips
                    WHERE is_pinned = 1
                )
                UPDATE clips
                SET pin_slot = (SELECT rn FROM ordered WHERE ordered.id = clips.id)
                WHERE is_pinned = 1
                  AND (SELECT rn FROM ordered WHERE ordered.id = clips.id) <= \(Constants.maxPinnedClips)
            """)
        }
    }
}
