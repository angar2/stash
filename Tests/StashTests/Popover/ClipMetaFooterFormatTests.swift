// ClipMetaFooterView 시간 포맷 + 출처 앱 fallback 단위 테스트 (TASK-039)
@testable import stash
import Testing
import Foundation
import AppKit

@Suite("ClipMetaFooter 포맷 + fallback (TASK-039)")
@MainActor
struct ClipMetaFooterFormatTests {

    // MARK: - 시간 포맷

    @Test("formatTime — yyyy-MM-dd HH:mm 절대 형식 출력")
    func timeFormatProducesYYYYMMDDHHmm() {
        // 2026-05-21 11:21:00 (UTC) — TimeZone.current 에 따라 KST 환경에서는 20:21 로 표시됨.
        // 검증 = *형식 정확성* (정확한 시각 값은 TZ 의존). yyyy-MM-dd HH:mm 패턴만 검증.
        let date = Date(timeIntervalSince1970: 1_779_703_260)
        let formatted = ClipMetaFooterView.formatTime(date)

        // 패턴 = YYYY-MM-DD HH:MM (16 자 — `2026-05-21 11:21` 형태)
        #expect(formatted.count == 16, "16자 형식 기대. 실제 '\(formatted)' (\(formatted.count)자)")
        // 정규 표현 — `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$`
        let regex = #/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/#
        #expect(formatted.wholeMatch(of: regex) != nil, "yyyy-MM-dd HH:mm 패턴 매칭 기대. 실제 '\(formatted)'")
    }

    @Test("formatTime — 동일 timestamp 입력 시 결정적 출력")
    func timeFormatDeterministic() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let f1 = ClipMetaFooterView.formatTime(date)
        let f2 = ClipMetaFooterView.formatTime(date)
        #expect(f1 == f2, "동일 timestamp → 동일 포맷 출력")
    }

    // MARK: - 출처 앱 fallback

    @Test("appDisplayName — bundleId nil → 'unknownApp' i18n 키 값 반환")
    func bundleIdNilReturnsUnknownApp() {
        let name = ClipMetaFooterView.appDisplayName(for: nil)
        let expected = String(localized: "clipDetail.meta.unknownApp")
        #expect(name == expected)
    }

    @Test("appDisplayName — bundleId 미해석 (존재 X 앱) → 'unknownApp' i18n 키 값 반환")
    func bundleIdNonExistentReturnsUnknownApp() {
        let name = ClipMetaFooterView.appDisplayName(for: "com.nonexistent.app.zzzz12345")
        let expected = String(localized: "clipDetail.meta.unknownApp")
        #expect(name == expected)
    }

    @Test("appDisplayName — 유효 bundleId (Finder) → FileManager.displayName 반환")
    func bundleIdValidReturnsDisplayName() {
        // macOS stock 앱 Finder = com.apple.finder
        let name = ClipMetaFooterView.appDisplayName(for: "com.apple.finder")
        // 한글/영문 환경 모두 빈 문자열 X + unknownApp i18n 아님
        let unknownApp = String(localized: "clipDetail.meta.unknownApp")
        #expect(!name.isEmpty)
        #expect(name != unknownApp)
    }

    @Test("appIcon — 유효 bundleId (Finder) → non-nil NSImage 반환")
    func bundleIdValidReturnsIcon() {
        let icon = ClipMetaFooterView.appIcon(for: "com.apple.finder")
        #expect(icon != nil)
    }

    @Test("appIcon — bundleId nil → nil 반환")
    func bundleIdNilReturnsNilIcon() {
        let icon = ClipMetaFooterView.appIcon(for: nil)
        #expect(icon == nil)
    }
}
