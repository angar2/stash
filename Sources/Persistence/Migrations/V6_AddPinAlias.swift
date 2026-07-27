// V6 — `pin_alias` 컬럼 추가 (TASK-098)
// 사유: 핀 항목에 표시용 명칭을 달아 Pin 사이드바·설정 PIN 단축키 행에서 값 대신 이름으로 식별하기 위함.
// 표시 전용 컬럼 — 붙여넣기·복사·검색·중복 판정은 본 컬럼을 참조하지 않는다 (DATA-MODEL §1 `pin_alias` 정책).
// 기존 row 자연 NULL — 미설정(값 표시) 상태이므로 기존 동작 무손실.
import GRDB

enum V6_AddPinAlias {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6_add_pin_alias") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "pin_alias", .text)
            }
        }
    }
}
