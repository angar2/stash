// 오픈소스 라이선스 고지 목록 검증 (TASK-111) — 라이선스 창에 실리는 라이브러리 구성과 전문 수록 확인
import Testing
@testable import stash

@Suite("OpenSourceLicenses")
struct OpenSourceLicensesTests {
    /// MIT 허가 조항 첫 문장. 세 라이브러리 원문 모두 이 문장을 담는다.
    private let mitPermission = "Permission is hereby granted, free of charge, to any person"

    @Test func listsBundledLibrariesInOrder() {
        #expect(OpenSourceLicenses.all.map(\.name) == ["KeyboardShortcuts", "GRDB", "Sparkle"])
    }

    /// TASK-112 — 코드 테스트는 dmg판(`Stash` 타깃)으로 빌드된다. 위 `all` 검증이 dmg판 목록을 보는 근거다.
    @Test func testBuildIsDirectDistribution() {
        #expect(AppDistribution.current == .direct)
    }

    /// TASK-112 — App Store판은 Sparkle 을 넣지 않으므로 라이선스 창에서도 뺀다. dmg판은 세 개 그대로다.
    @Test func listMatchesDistribution() {
        #expect(OpenSourceLicenses.list(for: .direct).map(\.name) == ["KeyboardShortcuts", "GRDB", "Sparkle"])
        #expect(OpenSourceLicenses.list(for: .appStore).map(\.name) == ["KeyboardShortcuts", "GRDB"])
    }

    @Test func everyEntryCarriesCopyrightAndMITPermission() {
        for license in OpenSourceLicenses.all {
            let flattened = license.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(flattened.contains(mitPermission), "\(license.name) 전문에 MIT 허가 조항이 없다")
            #expect(license.text.contains("Copyright"), "\(license.name) 전문에 저작권 표기가 없다")
            #expect(license.url.hasPrefix("https://github.com/"))
        }
    }

    /// Sparkle 은 LICENSE 파일에 함께 실린 외부 라이선스 고지까지 실어야 한다(BSD 조항의 고지 재현 요구).
    @Test func sparkleIncludesExternalLicenses() {
        let text = OpenSourceLicenses.sparkle.text
        #expect(text.contains("EXTERNAL LICENSES"))
        #expect(text.contains("Colin Percival"))
        #expect(text.contains("Yuta Mori"))
        #expect(text.contains("Orson Peters"))
        #expect(text.contains("Mark Hamlin"))
    }
}
