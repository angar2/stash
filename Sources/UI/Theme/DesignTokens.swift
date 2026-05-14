// stash 디자인 토큰 — Claude Design IMPLEMENTATION_HANDOFF.md §1 + project/ds/colors_and_type.css 추출본
// 라이트·다크 페어는 Color(light:dark:) 헬퍼로 시스템 외관 자동 추종 (UX-UI §12-4 §13 정합)
// Liquid Glass + 14~25 Material fallback 분기는 호출 측에서 @available(macOS 26.0, *) 처리
import SwiftUI
import AppKit

enum DesignTokens {

    // MARK: - Colors
    enum Colors {
        // popover 배경 (Liquid Glass over blur 50 + sat 200%)
        static let popoverBackground = Color(
            light: Color(red: 248/255, green: 247/255, blue: 250/255, opacity: 0.72),
            dark:  Color(red: 28/255,  green: 26/255,  blue: 38/255,  opacity: 0.62)
        )

        // 클립 행 선택 — 라이트는 linear-gradient(0.14 → 0.10) / 다크는 (0.32 → 0.32) (HANDOFF §1 색상 표 참조 — SwiftUI에서는 LinearGradient로 직접 박음)
        static let clipRowSelectionTop = Color(
            light: Color(red: 13/255,  green: 111/255, blue: 255/255, opacity: 0.14),
            dark:  Color(red: 64/255,  green: 140/255, blue: 255/255, opacity: 0.32)
        )
        static let clipRowSelectionBottom = Color(
            light: Color(red: 13/255,  green: 111/255, blue: 255/255, opacity: 0.10),
            dark:  Color(red: 40/255,  green: 110/255, blue: 230/255, opacity: 0.32)
        )
        // 선택 행 inset 보더
        static let clipRowSelectionBorder = Color(
            light: Color(red: 13/255,  green: 111/255, blue: 255/255, opacity: 0.22),
            dark:  Color(red: 80/255,  green: 150/255, blue: 255/255, opacity: 0.35)
        )

        // paste 플래시 (~700ms green flash)
        static let pasteFlash = Color(
            light: Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.16),
            dark:  Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.30)
        )

        // 시스템 accent (system 자동 추종이 default — 정적 상수는 fallback / 디자인 명시값)
        static let accent = Color(red: 13/255, green: 111/255, blue: 255/255)  // #0D6FFF
        static let accentForeground = Color.white

        // 본문 / 보조 fg
        static let labelPrimary = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.88),
            dark:  Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 0.94)
        )
        static let labelSecondary = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.50),
            dark:  Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 0.50)
        )

        // 구분선
        static let divider = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 0.07)
        )

        // 환경설정 행 hover (라이트만 — 다크는 시스템 표준 동작)
        static let preferenceRowHover = Color(red: 0, green: 0, blue: 0, opacity: 0.03)

        // Toast kind 색상 (alpha 0.3 보더 + 18×18 원형 배지)
        static let toastSuccess = Color(red: 48/255,  green: 209/255, blue: 88/255)   // 그린 ✓
        static let toastInfo    = Color(red: 13/255,  green: 111/255, blue: 255/255)  // 블루 i
        static let toastWarn    = Color(red: 255/255, green: 149/255, blue: 0/255)    // 오렌지 !
        static let toastError   = Color(red: 255/255, green: 56/255,  blue: 60/255)   // 레드 ×

        // Toast 배경
        static let toastBackground = Color(
            light: Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 0.86),
            dark:  Color(red: 30/255,  green: 30/255,  blue: 34/255,  opacity: 0.86)
        )
    }

    // MARK: - Typography
    // 사용처별 사이즈 / 굵기 페어. SF Pro / SF Mono 시스템 폰트 추종.
    enum Typography {
        // 브랜드 워드마크 (stash 로고)
        static let brandWordmark   = Font.system(size: 13, weight: .heavy)
        // 클립 본문 — 텍스트
        static let clipBody        = Font.system(size: 13, weight: .medium)
        // 클립 본문 — mono (code-like content, SF Mono)
        static let clipBodyMono    = Font.system(size: 12.5, weight: .medium, design: .monospaced)
        // 행 헤더 (Pin 목록, 환경설정)
        static let rowHeader       = Font.system(size: 12.5, weight: .medium)
        static let rowHeaderBold   = Font.system(size: 12.5, weight: .semibold)
        // 시간 메타
        static let timeMeta        = Font.system(size: 10.5, weight: .medium)
        // 키캡
        static let keycap          = Font.system(size: 9, weight: .semibold, design: .monospaced)
        // 빈 상태 안내
        static let emptyHint       = Font.system(size: 12, weight: .medium)
        // 설정 윈도우 본문 / 보조
        static let settingsBody    = Font.system(size: 13, weight: .medium)
        static let settingsCaption = Font.system(size: 11, weight: .regular)
    }

    // MARK: - Spacing (4-pt grid — css :root spacing token 정합)
    enum Spacing {
        static let xs:  CGFloat = 4   // --space-1
        static let sm:  CGFloat = 8   // --space-2
        static let md:  CGFloat = 12  // --space-3
        static let lg:  CGFloat = 16  // --space-4
        static let xl:  CGFloat = 20  // --space-5
        static let xxl: CGFloat = 24  // --space-6
        // stash 전용 — popover 내부
        static let popoverPadding:    CGFloat = 6
        static let rowGap:            CGFloat = 2
        static let rowPaddingSingle:  CGFloat = 12  // horizontal (vertical 0)
        static let rowPaddingMultiH:  CGFloat = 12
        static let rowPaddingMultiV:  CGFloat = 8
        static let rowMinHeight:      CGFloat = 44
        static let pinSidebarGap:     CGFloat = 10  // popover 왼쪽 간격
    }

    // MARK: - Radius (모서리 라운드)
    enum Radius {
        static let popoverOuter:    CGFloat = 18  // popover 외곽
        static let clipRow:         CGFloat = 12  // 클립 행
        static let keycap:          CGFloat = 3.5
        // 시스템 표준 radii (CSS --radius-* 정합)
        static let xs:  CGFloat = 3
        static let sm:  CGFloat = 5
        static let md:  CGFloat = 6
        static let lg:  CGFloat = 8
        static let xl:  CGFloat = 10  // 표준 윈도우 / sheet
        static let xxl: CGFloat = 12
        static let glassPill: CGFloat = 22  // dock pill / large glass
    }

    // MARK: - WindowSize (HANDOFF §1 윈도우 크기 표)
    enum WindowSize {
        // popover (방식 1/3 — NSPopover, NSPanel) / (방식 2 미니멀) — 동일 가로폭
        static let popoverWidth:        CGFloat = 380
        // Pin 사이드 메뉴
        static let pinSidebarWidth:     CGFloat = 220
        // 환경설정 윈도우 — 너비 620 / 최대 높이 480 + 탭바·타이틀바 ≒ 580
        static let settingsWidth:       CGFloat = 620
        static let settingsHeightMax:   CGFloat = 580
        static let settingsContentMaxH: CGFloat = 480
        // onboarding 윈도우 — 480 가운데 정렬
        static let onboardingWidth:     CGFloat = 480
        // 토스트 (가변 폭)
        static let toastMinWidth:       CGFloat = 260
        static let toastMaxWidth:       CGFloat = 360
        static let toastInsetTop:       CGFloat = 38  // 메뉴바 아래
        static let toastInsetRight:     CGFloat = 20
        // 키캡 최소 크기
        static let keycapMin:           CGFloat = 14
    }

    // MARK: - Shadow
    // SwiftUI .shadow(color:radius:x:y:) 적용 시 사용
    enum Shadow {
        // popover 그림자 (라이트)
        static let popoverColor    = Color(red: 0, green: 0, blue: 0, opacity: 0.30)
        static let popoverColorDark = Color(red: 0, green: 0, blue: 0, opacity: 0.55)
        static let popoverRadius:  CGFloat = 35  // 70px blur → SwiftUI radius 절반 근사
        static let popoverOffsetY: CGFloat = 22

        // popover inset white 하이라이트 (별도 RoundedRectangle stroke 적용)
        static let popoverInsetHighlight = Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 0.60)
        static let popoverInsetHighlightDark = Color(red: 255/255, green: 255/255, blue: 255/255, opacity: 0.08)

        // popover outer black 보더
        static let popoverOuterStroke = Color(red: 0, green: 0, blue: 0, opacity: 0.10)
        static let popoverOuterStrokeDark = Color(red: 0, green: 0, blue: 0, opacity: 0.50)

        // 시스템 표준 shadow (CSS --shadow-* 정합)
        // control
        static let controlColor:  Color  = Color(red: 0, green: 0, blue: 0, opacity: 0.20)
        static let controlRadius: CGFloat = 0.5
        // window
        static let windowColor:   Color  = Color(red: 0, green: 0, blue: 0, opacity: 0.35)
        static let windowRadius:  CGFloat = 30
        static let windowOffsetY: CGFloat = 24
        // glass
        static let glassColor:    Color  = Color(red: 0, green: 0, blue: 0, opacity: 0.12)
        static let glassRadius:   CGFloat = 20
        static let glassOffsetY:  CGFloat = 8
    }

    // MARK: - Animation timing (UX-UI §11-2 / HANDOFF §4-4·§8 정합)
    enum Animation {
        // Pin 사이드 펼침 — 200ms 지연 + slide
        static let pinSidebarDelay: Double  = 0.2
        static let pinSidebarDuration: Double = 0.18  // 180ms cubic-bezier(0.2,0.7,0.3,1)
        // paste 직후 초록 플래시
        static let pasteFlashDuration: Double = 0.7  // 700ms
        // 토스트 default TTL
        static let toastTTLDefault: Double = 3.0     // 3000ms
        static let toastTTLShort:   Double = 1.8     // paste 확정
        static let toastTTLLong:    Double = 2.2     // 전체 삭제 등
    }
}

// MARK: - Color light/dark pair 헬퍼
extension Color {
    /// 시스템 외관 (Aqua / Dark Aqua) 자동 추종으로 라이트·다크 페어 분기.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}
