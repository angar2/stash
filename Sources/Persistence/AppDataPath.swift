// 앱 데이터 경로 캡슐화 — Sandbox 마이그레이션 대비 단일 진실 소스
import Foundation

enum AppDataPath {
    /// XCUITest 격리용 임시 데이터 폴더 (`--ui-test --isolated-data-folder` 인자 동반 시 사용).
    /// 일반 사용자 launch 흐름에서는 nil — Application Support 경로 자연 사용.
    /// `nonisolated(unsafe)` 사유: `StashApp.init()` 진입부에서 `setIsolatedOverride` 1회 호출 후 read-only.
    /// 이후 모든 호출자는 read 전용 — race condition 없음.
    nonisolated(unsafe) private static var isolatedOverride: URL?

    static func dataFolder() -> URL {
        if let override = isolatedOverride { return override }
        return FileManager.default
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

    /// TASK-089 Phase 1 — XCUITest 격리 환경 진입 시 1회 호출. `StashApp.init()` 진입부에서 실행.
    /// 일반 사용자 launch 흐름에서는 호출 X.
    static func setIsolatedOverride(_ url: URL) {
        isolatedOverride = url
    }

    /// 테스트 격리용 — 캐시된 isolated override reset. 일반 앱 흐름에서는 호출 X.
    static func resetIsolatedOverrideForTesting() {
        isolatedOverride = nil
    }
}
