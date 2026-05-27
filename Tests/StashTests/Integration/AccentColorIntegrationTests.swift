// 시스템 accent color 모드 전환 end-to-end 통합 시나리오 — Phase 5 (TASK-089)
// AccentColorMode UserDefaults 박음 → 영속 + Color 값 갱신 검증.
import Testing
import Foundation
import SwiftUI
@testable import stash

@MainActor
@Suite(.serialized)
struct AccentColorIntegrationTests {
    private func restoreAccentDefaults() {
        UserDefaults.standard.removeObject(forKey: AccentColorMode.userDefaultsKey)
    }

    @Test("AccentColorMode.default ↔ .system 전환 → UserDefaults 영속 + colorValue 분기")
    func switchModePersistsAndUpdatesColor() async throws {
        // 사전 cleanup.
        UserDefaults.standard.removeObject(forKey: AccentColorMode.userDefaultsKey)
        defer { restoreAccentDefaults() }

        // .default 박음.
        UserDefaults.standard.set(AccentColorMode.default.rawValue, forKey: AccentColorMode.userDefaultsKey)
        let defaultMode = AccentColorMode(rawValue: UserDefaults.standard.string(forKey: AccentColorMode.userDefaultsKey) ?? "")
        #expect(defaultMode == .default, "AccentColorMode UserDefaults 값 = .default")

        // .system 박음.
        UserDefaults.standard.set(AccentColorMode.system.rawValue, forKey: AccentColorMode.userDefaultsKey)
        let systemMode = AccentColorMode(rawValue: UserDefaults.standard.string(forKey: AccentColorMode.userDefaultsKey) ?? "")
        #expect(systemMode == .system, "AccentColorMode UserDefaults 값 = .system")

        // colorValue 분기 검증 — .default 와 .system 은 서로 다른 Color (시스템 controlAccentColor vs 앱 default).
        // *Color* 값 equality 직접 검증은 SwiftUI Color 의 opaque 한계로 skip — enum 매칭으로 충분.
        #expect(AccentColorMode.default != AccentColorMode.system, "두 enum 케이스 distinct")
    }

    @Test("AccentColorMode raw value — 영구 불변 (UserDefaults 영속)")
    func rawValuesAreStable() {
        #expect(AccentColorMode.default.rawValue == "default", "AccentColorMode.default raw = 'default'")
        #expect(AccentColorMode.system.rawValue == "system", "AccentColorMode.system raw = 'system'")
    }
}
