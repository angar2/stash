// 앱 데이터 경로 캡슐화 — Sandbox 마이그레이션 대비 단일 진실 소스
import Foundation

enum AppDataPath {
    static func dataFolder() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("stash")
    }

    static func databaseFile() -> URL {
        dataFolder().appendingPathComponent("clips.sqlite")
    }

    static func clipsFolder() -> URL {
        dataFolder().appendingPathComponent("clips")
    }

    static func corruptionBackupFile(timestamp: Date) -> URL {
        let iso = ISO8601DateFormatter().string(from: timestamp)
        return dataFolder().appendingPathComponent("clips.sqlite.bak.\(iso)")
    }
}
