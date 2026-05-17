// V4 — `file_paths_json` 컬럼 추가 (TASK-026)
// 사유: 다중 파일 묶음 (Finder 등에서 N개 파일 동시 ⌘C) 을 단일 클립 행에 저장 위해 ClipFileEntry 배열 JSON 직렬화 컬럼 도입.
// 기존 row 자연 NULL — 단일 파일 호환 무손실.
import GRDB

enum V4_AddFilePathsJson {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_add_file_paths_json") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "file_paths_json", .text)
            }
        }
    }
}
