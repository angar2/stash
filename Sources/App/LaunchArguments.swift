// XCUITest 자동화용 launch argument 파싱 + 테스트 환경 분기 (TASK-089 Phase 1)
import Foundation
import OSLog

/// XCUITest 통합 테스트에서 앱 launch 시 주입하는 인자 파싱 + 격리 환경 설정.
/// 일반 사용자 launch (인자 0건) 흐름과 완전 분리 — `isUITest` false 면 모든 분기 no-op.
enum LaunchArguments {

    // MARK: - 인자 키 (XCUIApplication.launchArguments 에 박힘)

    static let uiTest = "--ui-test"
    static let resetOnboarding = "--reset-onboarding"
    static let showPopover = "--show-popover"
    static let showSettings = "--show-settings"
    static let isolatedDataFolder = "--isolated-data-folder"
    /// `--seed-clips=N` — N 개 시드 클립을 in-memory 가상 데이터로 박음. 0 또는 미지정 시 시드 X.
    static let seedClipsPrefix = "--seed-clips="
    /// `--language=ko` / `--language=en` — AppLanguageService override.
    static let languagePrefix = "--language="

    // MARK: - 파싱 결과 캐시 (init 1회)

    /// `nonisolated(unsafe)` 사유: `StashApp.init()` 진입부에서 `parse()` 1회 호출 후 cache hit (read-only).
    /// 이후 모든 호출자는 read 전용 — race condition 없음.
    nonisolated(unsafe) private static var cachedSnapshot: Snapshot?

    struct Snapshot: Sendable {
        let isUITest: Bool
        let resetOnboarding: Bool
        let showPopover: Bool
        let showSettings: Bool
        let isolatedDataFolder: Bool
        let seedClipsCount: Int
        let languageOverride: String?
    }

    /// 앱 init 진입부에서 1회 호출. `ProcessInfo.processInfo.arguments` 파싱.
    @discardableResult
    static func parse() -> Snapshot {
        if let cached = cachedSnapshot { return cached }
        let args = ProcessInfo.processInfo.arguments
        let isUITest = args.contains(uiTest)
        let snapshot = Snapshot(
            isUITest: isUITest,
            resetOnboarding: isUITest && args.contains(resetOnboarding),
            showPopover: isUITest && args.contains(showPopover),
            showSettings: isUITest && args.contains(showSettings),
            isolatedDataFolder: isUITest && args.contains(isolatedDataFolder),
            seedClipsCount: isUITest ? parseIntPrefix(args, prefix: seedClipsPrefix) ?? 0 : 0,
            languageOverride: isUITest ? parseStringPrefix(args, prefix: languagePrefix) : nil
        )
        cachedSnapshot = snapshot
        if isUITest {
            Logger.appLifecycle.info("LaunchArguments parsed (UI test mode): reset=\(snapshot.resetOnboarding) popover=\(snapshot.showPopover) settings=\(snapshot.showSettings) isolated=\(snapshot.isolatedDataFolder) seed=\(snapshot.seedClipsCount) lang=\(snapshot.languageOverride ?? "-", privacy: .public)")
        }
        return snapshot
    }

    /// 캐시 reset — 테스트 격리용. 일반 앱 흐름에서는 호출 X.
    static func resetCacheForTesting() {
        cachedSnapshot = nil
    }

    /// UI 테스트 모드 진입 시 사전 환경 정리 — UserDefaults reset / 격리 데이터 폴더 박음 등.
    /// `StashApp.init()` 가장 먼저 호출.
    static func applyEarlyEnvironment() {
        let snapshot = parse()
        guard snapshot.isUITest else { return }

        if snapshot.isolatedDataFolder {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("stash-ui-test-\(UUID().uuidString)")
            AppDataPath.setIsolatedOverride(tmp)
            Logger.appLifecycle.info("UI test: isolated data folder = \(tmp.path, privacy: .public)")
        }

        if snapshot.resetOnboarding {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
            Logger.appLifecycle.info("UI test: onboarding flag reset")
        }

        if let lang = snapshot.languageOverride {
            UserDefaults.standard.set(lang, forKey: "appLanguage")
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
            Logger.appLifecycle.info("UI test: language override = \(lang, privacy: .public)")
        }
    }

    // MARK: - 헬퍼

    private static func parseIntPrefix(_ args: [String], prefix: String) -> Int? {
        guard let raw = args.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let value = raw.dropFirst(prefix.count)
        return Int(value)
    }

    private static func parseStringPrefix(_ args: [String], prefix: String) -> String? {
        guard let raw = args.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let value = String(raw.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}
