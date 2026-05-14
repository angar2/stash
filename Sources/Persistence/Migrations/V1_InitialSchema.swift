// GRDB DatabaseMigrator V1 초기 스키마 — clips 테이블 + 인덱스 (DATA-MODEL §8 정합)
import GRDB

enum V1_InitialSchema {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "clips") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("body", .text)
                t.column("file_path", .text)
                t.column("is_file_external", .boolean).notNull().defaults(to: false)
                t.column("file_original_path", .text)
                t.column("file_bookmark", .blob)
                t.column("source_app_bundle_id", .text)
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("last_used_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_clips_pinned_last_used",
                on: "clips",
                columns: ["is_pinned", "last_used_at"]
            )
        }
    }
}
