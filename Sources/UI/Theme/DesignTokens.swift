// stash 디자인 토큰 — Claude Design 산출 (Interactive Prototype.html + popover.jsx + settings.jsx + onboarding-toast.jsx + icons.jsx + colors_and_type.css) 100% 정합
// 라이트·다크 페어는 Color(light:dark:) 헬퍼로 시스템 외관 자동 추종 (UX-UI §12-4 시각 = 디자인 우선 정합)
// Liquid Glass + 14~25 Material fallback 분기는 VisualEffectView wrapper에서 처리
import SwiftUI
import AppKit

enum DesignTokens {

    // MARK: - Colors
    enum Colors {
        // ─── 시스템 accent ─────────────────────────────────────────────
        static let accent = Color(red: 13/255, green: 111/255, blue: 255/255)  // #0D6FFF (popover.jsx L11)
        static let accentForeground = Color.white
        // 앱 아이콘 그라데이션 보조 (적층 카드 보라 톤)
        static let appIconAccent = Color(red: 100/255, green: 50/255, blue: 200/255)
        static let primaryButtonStart = Color(red: 45/255, green: 134/255, blue: 245/255)  // 그라데이션 상단

        // ─── popover / sidebar 배경 (Liquid Glass over blur 50 + sat 200%) — popover.jsx L280-292 ───
        static let popoverBackground = Color(
            light: Color(red: 248/255, green: 247/255, blue: 250/255, opacity: 0.72),
            dark:  Color(red: 28/255,  green: 26/255,  blue: 38/255,  opacity: 0.62)
        )

        // ─── 클립 행 선택 그라데이션 (linear-gradient 180deg) — popover.jsx L52-58 ───
        static let clipRowSelectionTop = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.14),
            dark:  Color(red: 64/255, green: 140/255, blue: 255/255, opacity: 0.32)
        )
        static let clipRowSelectionBottom = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.10),
            dark:  Color(red: 40/255, green: 110/255, blue: 230/255, opacity: 0.32)
        )
        // 선택 행 inset 보더
        static let clipRowSelectionBorder = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.22),
            dark:  Color(red: 80/255, green: 150/255, blue: 255/255, opacity: 0.35)
        )

        // ─── paste 직후 700ms 초록 플래시 — popover.jsx L60-66 ───
        static let pasteFlash = Color(
            light: Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.16),
            dark:  Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.30)
        )
        static let pasteFlashBorder = Color(
            light: Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.40),
            dark:  Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.45)
        )

        // ─── 본문 / 보조 fg ───────────────────────────────────────────
        static let labelPrimary = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.88),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.94)
        )
        static let labelSecondary = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.50),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.50)
        )
        // 워드마크 본문
        static let labelWordmark = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.78),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
        )
        // 클립 보조 아이콘 (비선택)
        static let clipIconUnselected = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.45),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.55)
        )
        // 시간 메타 — labelSecondary 동일

        // 빈 상태 큰 제목
        static let emptyTitleColor = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.70),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
        )
        // 빈 상태 보조
        static let emptyHintColor = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.45),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.50)
        )
        // 빈 상태 큰 트레이 아이콘 색
        static let emptyTrayIcon = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.30),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.45)
        )
        // 빈 상태 round 컨테이너 bg
        static let emptyContainerBg = Color(
            light: Color(red: 1, green: 1, blue: 1, opacity: 0.60),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.05)
        )

        // ─── 구분선 ───────────────────────────────────────────────────
        static let divider = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.07)
        )

        // ─── 검색바 ───────────────────────────────────────────────────
        // focus 없음
        static let searchBoxBg = Color(
            light: Color(red: 1, green: 1, blue: 1, opacity: 0.70),
            dark:  Color(red: 0, green: 0, blue: 0, opacity: 0.25)
        )
        // 보더 (focus X)
        static let searchBoxBorder = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.04),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.07)
        )
        // searchFocused 시 보더 (파란 라인)
        static let searchBoxFocusedBorder = Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.50)
        // searchFocused 시 outer ring
        static let searchBoxFocusedRing = Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.22)

        // 검색 아이콘 (비활성)
        static let searchIconInactive = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.45),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.50)
        )

        // ─── Pin 행 헤더 색 ───────────────────────────────────────────
        static let pinRowHeader = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.75),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
        )
        static let pinRowBadgeBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.08)
        )
        // Pin Row 우측 단축키 안내 키캡 배경 — TASK-019
        static let pinRowKeycapBg = Color(
            light: Color.white.opacity(0.6),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.06)
        )

        // ─── 환경설정 행 색 ──────────────────────────────────────────
        static let preferencesRow = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.50),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.60)
        )

        // ─── 클립 행 액션 (Pin/X 버튼) ───────────────────────────────
        // 선택된 행의 X 버튼 bg
        static let clipDeleteBg = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.10),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.10)
        )
        /// X 버튼 hover 시 배경 — baseline opacity 0.10 → 0.22 (시각 피드백).
        static let clipDeleteBgHover = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.22),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.22)
        )
        // 선택된 행의 X 아이콘
        static let clipDeleteIcon = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
        )
        // 선택된 행의 typeIcon (강조)
        static let clipTypeIconSelected = Color(
            light: Color(red: 13/255, green: 111/255, blue: 255/255),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
        )
        // 검색바 안 "전체 삭제" 텍스트 버튼
        static let searchDeleteAllLabel = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.30),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.35)
        )
        /// 전체 삭제 버튼 hover 시 — opacity 진해짐 (시각 피드백).
        static let searchDeleteAllLabelHover = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.65),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
        )

        // ─── Pin Sidebar 헤더 ────────────────────────────────────────
        static let pinSidebarHeader = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.40),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.45)
        )

        // ─── 키캡 ────────────────────────────────────────────────────
        static let keycapBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.10)
        )
        static let keycapFg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.52),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.62)
        )
        static let keycapInset = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.05),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.05)
        )
        // 힌트 라벨
        static let hintLabel = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.42),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.45)
        )
        // "or" 색
        static let hintOr = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.36),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.40)
        )

        // ─── 이미지 클립 그라데이션 (135deg #FFB37A 0% #F47B4E 50% #C44A8B 100%) — popover.jsx L84 ───
        static let imageGradientStart = Color(red: 255/255, green: 179/255, blue: 122/255)
        static let imageGradientMid   = Color(red: 244/255, green: 123/255, blue: 78/255)
        static let imageGradientEnd   = Color(red: 196/255, green: 74/255, blue: 139/255)

        // ─── Toast 4 kind — onboarding-toast.jsx L219-224 ────────────
        static let toastSuccess = Color(red: 48/255,  green: 209/255, blue: 88/255)   // #30D158
        static let toastInfo    = Color(red: 13/255,  green: 111/255, blue: 255/255)  // #0D6FFF
        static let toastWarn    = Color(red: 255/255, green: 149/255, blue: 0/255)    // #FF9500
        static let toastError   = Color(red: 255/255, green: 56/255,  blue: 60/255)   // #FF383C

        // Toast 배경
        static let toastBackground = Color(
            light: Color(red: 1, green: 1, blue: 1, opacity: 0.86),
            dark:  Color(red: 30/255, green: 30/255, blue: 34/255, opacity: 0.86)
        )
        // Toast kind별 bg (라이트/다크 페어)
        static func toastBg(kind: ToastKindToken) -> Color {
            switch kind {
            case .success: return Color(
                light: Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.10),
                dark:  Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.12)
            )
            case .info: return Color(
                light: Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.08),
                dark:  Color(red: 13/255, green: 111/255, blue: 255/255, opacity: 0.12)
            )
            case .warn: return Color(
                light: Color(red: 255/255, green: 149/255, blue: 0/255, opacity: 0.10),
                dark:  Color(red: 255/255, green: 149/255, blue: 0/255, opacity: 0.14)
            )
            case .error: return Color(
                light: Color(red: 255/255, green: 56/255, blue: 60/255, opacity: 0.10),
                dark:  Color(red: 255/255, green: 56/255, blue: 60/255, opacity: 0.14)
            )
            }
        }
        // Toast 닫기 X 색
        static let toastDismissColor = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.35),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.40)
        )

        // Settings 배경 — settings.jsx L444-456 + L460-481 + L484-489
        static let settingsBackground = Color(
            light: Color(red: 246/255, green: 246/255, blue: 248/255, opacity: 0.96),
            dark:  Color(red: 30/255,  green: 30/255,  blue: 34/255,  opacity: 0.96)
        )
        static let settingsTitlebar = Color(
            light: Color(red: 238/255, green: 237/255, blue: 242/255, opacity: 0.78),
            dark:  Color(red: 38/255,  green: 38/255,  blue: 42/255,  opacity: 0.78)
        )
        static let settingsTabbar = Color(
            light: Color(red: 238/255, green: 237/255, blue: 242/255, opacity: 0.55),
            dark:  Color(red: 38/255,  green: 38/255,  blue: 42/255,  opacity: 0.55)
        )
        static let settingsRowDivider = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.08),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.06)
        )
        static let settingsCardBg = Color(
            light: Color.white,
            dark:  Color(red: 20/255, green: 20/255, blue: 24/255, opacity: 0.50)
        )
        // 탭 selection bg
        static let settingsTabSelectedBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.10)
        )
        static let settingsTabUnselectedIcon = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.62),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.70)
        )

        // Toggle / Radio
        static let toggleOnBg = Color(red: 48/255, green: 209/255, blue: 88/255)  // #30D158
        static let toggleOffBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.15),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.15)
        )

        // Onboarding 배경 — onboarding-toast.jsx L22-31
        static let onboardingBackground = Color(
            light: Color(red: 252/255, green: 252/255, blue: 255/255, opacity: 0.98),
            dark:  Color(red: 30/255,  green: 30/255,  blue: 34/255,  opacity: 0.98)
        )
        static let onboardingBackdrop = Color(red: 0, green: 0, blue: 0, opacity: 0.35)
        // 진행 도트 비활성
        static let progressDotInactive = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.12),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.15)
        )

        // Onboarding 권한 large icon — 대기 상태
        static let permissionIconBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.05),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.08)
        )
    }

    // Toast kind enum (DesignTokens 내부용 — UI 파일에선 별도 ToastKind 사용)
    enum ToastKindToken {
        case success, info, warn, error
    }

    // MARK: - Typography (popover.jsx + settings.jsx + onboarding-toast.jsx 정합)
    enum Typography {
        // 워드마크 "stash" — popover.jsx L321-326
        static let brandWordmark   = Font.system(size: 13, weight: .heavy).leading(.tight)
        // 클립 본문 (text)
        static let clipBody        = Font.system(size: 13, weight: .medium)
        // 클립 본문 (mono — code-like)
        static let clipBodyMono    = Font.system(size: 12.5, weight: .medium, design: .monospaced)
        // 행 헤더 (Pin 목록 / 환경설정)
        static let rowHeader       = Font.system(size: 12.5, weight: .medium)
        static let rowHeaderBold   = Font.system(size: 12.5, weight: .semibold)
        // 시간 메타 (tabular-nums)
        static let timeMeta        = Font.system(size: 10.5, weight: .medium)
        // 키캡
        static let keycap          = Font.system(size: 9, weight: .semibold, design: .monospaced)
        // Pin Row 우측 단축키 안내 키캡 — TASK-019 (hint bar keycap 보다 약간 큰 ⌘B 표시)
        static let pinRowKeycap    = Font.system(size: 10, weight: .semibold, design: .monospaced)
        // 힌트 라벨
        static let hintLabel       = Font.system(size: 9.5, weight: .medium)
        // 빈 상태 큰 제목
        static let emptyTitle      = Font.system(size: 13.5, weight: .semibold)
        // 빈 상태 보조
        static let emptyHint       = Font.system(size: 12, weight: .medium)

        // Pin Sidebar 헤더 (UPPERCASE tracking 0.08em)
        static let pinSidebarHeader = Font.system(size: 10, weight: .heavy)
        // Pin Sidebar 항목 카운트 뱃지
        static let pinSidebarBadge = Font.system(size: 10, weight: .bold)

        // Settings — settings.jsx L46-100
        static let settingsTitle    = Font.system(size: 13, weight: .semibold)
        static let settingsBody     = Font.system(size: 13, weight: .medium)
        static let settingsCaption  = Font.system(size: 11, weight: .regular)
        static let settingsHint     = Font.system(size: 11, weight: .regular)
        static let settingsTabLabel = Font.system(size: 11, weight: .semibold)

        // Onboarding — onboarding-toast.jsx L60-204
        static let onboardingTitleLarge = Font.system(size: 22, weight: .bold)
        static let onboardingTitleMid   = Font.system(size: 18, weight: .bold)
        static let onboardingBody       = Font.system(size: 13.5, weight: .regular)
        static let onboardingButtonText = Font.system(size: 13, weight: .semibold)
        static let onboardingCardTitle  = Font.system(size: 13, weight: .semibold)
        static let onboardingCardDesc   = Font.system(size: 11.5, weight: .regular)

        // Toast — onboarding-toast.jsx L257
        static let toastBody = Font.system(size: 12.5, weight: .medium)
    }

    // MARK: - Spacing (popover.jsx + settings.jsx + onboarding-toast.jsx 정합)
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 20
        static let xxl: CGFloat = 24

        // popover 내부 (popover.jsx L282 padding: 6 + L315 wordmark padding 8/12/2 + L329 search container padding 4/6/8)
        static let popoverPadding:        CGFloat = 6
        /// popover 내부 모든 행(검색·클립·Pin·환경설정)의 *공통* 좌우 outer inset (TASK-018 Phase 7).
        /// hover 시 background 활성 영역의 가로 폭을 4 영역 모두 일관되게 박는 단일 진실 소스. 검색 박스 영역과 일치.
        static let rowOuterHorzInset:     CGFloat = 6
        static let wordmarkPaddingTop:    CGFloat = 8
        static let wordmarkPaddingBottom: CGFloat = 2
        static let wordmarkPaddingHorz:   CGFloat = 12
        static let wordmarkIconLabelGap:  CGFloat = 5

        static let searchContainerPaddingHorz: CGFloat = 6
        static let searchContainerPaddingTop:  CGFloat = 4
        static let searchContainerPaddingBottom: CGFloat = 8
        static let searchBoxHeight:        CGFloat = 30
        static let searchBoxPaddingHorz:   CGFloat = 10
        static let searchBoxIconGap:       CGFloat = 8

        // 클립 행 (popover.jsx L75-87)
        static let rowMinHeight:           CGFloat = 44
        static let rowPaddingSingleH:      CGFloat = 12  // 단일줄 vertical 0
        static let rowPaddingMultiH:       CGFloat = 12
        static let rowPaddingMultiV:       CGFloat = 8
        static let rowGap:                 CGFloat = 2
        static let rowInnerGap:            CGFloat = 10
        static let rowTrailingGap:         CGFloat = 8

        // Pin 행 (popover.jsx L423-467)
        static let pinRowHeight:           CGFloat = 38
        static let pinRowPaddingHorz:      CGFloat = 12
        static let pinRowMarginVert:       CGFloat = 2

        // 환경설정 행 (popover.jsx L470-497)
        static let preferencesRowHeight:   CGFloat = 32
        static let preferencesRowPadHorz:  CGFloat = 12
        static let preferencesRowMarginTop: CGFloat = 2

        // 힌트바 (popover.jsx L165-207)
        static let hintsBarPaddingTop:     CGFloat = 5
        static let hintsBarPaddingHorz:    CGFloat = 10
        static let hintsBarPaddingBottom:  CGFloat = 4
        static let hintsGroupGap:          CGFloat = 10
        static let hintsKeycapToLabelGap:  CGFloat = 3
        static let hintsLabelMarginLeft:   CGFloat = 2

        // Pin Sidebar (popover.jsx L539-595)
        static let pinSidebarGap:          CGFloat = 2   // popover 왼쪽 간격 (TASK-019 fix 6차 — 10 → 2, 사용자 요구)
        static let pinSidebarPadding:      CGFloat = 6
        static let pinSidebarHeaderPadTop: CGFloat = 8
        static let pinSidebarHeaderPadBottom: CGFloat = 6
        static let pinSidebarItemHeight:   CGFloat = 36
        static let pinSidebarItemPadH:     CGFloat = 10
        static let pinSidebarItemGap:      CGFloat = 8
        // Pin sidebar 동적 height 계산 상수 (TASK-019 fix 2차 ~ 6차 — `PopoverWindow.computePinSidebarHeight`)
        static let pinSidebarHeaderHeight: CGFloat = 32  // 헤더 ("Pin 목록 · N") 영역 height
        static let pinSidebarHeightSafety: CGFloat = 20  // outer padding 위에 추가 안전 여유
        static let pinSidebarHeightBottomMargin: CGFloat = 40  // popoverHeight 와의 최소 간격 (사이드바가 본체보다 항상 작게)

        // 단축키 키캡 (Pin Row 우측 `⌘B` 안내 등 — TASK-019)
        static let keycapPaddingHorz:      CGFloat = 5
        static let keycapPaddingVert:      CGFloat = 1
        static let keycapStrokeWidth:      CGFloat = 0.5

        // 빈 상태 (popover.jsx L386-406)
        static let emptyPaddingTop:        CGFloat = 48
        static let emptyPaddingBottom:     CGFloat = 44
        static let emptyPaddingHorz:       CGFloat = 20
        static let emptyContainerSize:     CGFloat = 84
        static let emptyContainerToTitle:  CGFloat = 16
        static let emptyTitleToHint:       CGFloat = 3
        static let emptyIconSize:          CGFloat = 44

        // Settings
        static let settingsTitlebarHeight: CGFloat = 42
        static let settingsTitlebarPadH:   CGFloat = 14
        static let settingsTitlebarGap:    CGFloat = 10
        static let settingsTabbarPadH:     CGFloat = 14
        static let settingsTabbarPadTop:   CGFloat = 10
        static let settingsTabbarPadBottom: CGFloat = 12
        static let settingsTabGap:         CGFloat = 4
        static let settingsTabWidth:       CGFloat = 78
        static let settingsTabPadHorz:     CGFloat = 4
        static let settingsTabPadVert:     CGFloat = 6
        static let settingsContentMargin:  CGFloat = 18
        static let settingsRowPaddingH:    CGFloat = 16
        static let settingsRowPaddingV:    CGFloat = 12
        static let settingsLabelWidth:     CGFloat = 200

        // Onboarding
        static let onboardingPadH:         CGFloat = 36
        static let onboardingProgressGap:  CGFloat = 6
        static let onboardingCardGap:      CGFloat = 10
        static let onboardingCardPadV:     CGFloat = 12
        static let onboardingCardPadH:     CGFloat = 14
        static let onboardingCardInnerGap: CGFloat = 14

        // Toast
        static let toastPaddingHorz:       CGFloat = 14
        static let toastPaddingVert:       CGFloat = 10
        static let toastGap:               CGFloat = 10
        static let toastBadgeSize:         CGFloat = 18
        static let toastStackGap:          CGFloat = 8
        static let toastWindowPadding:     CGFloat = 8
    }

    // MARK: - Radius
    enum Radius {
        // popover / sidebar 외곽 — popover.jsx L283
        static let popoverOuter:    CGFloat = 18
        // 클립 행 / Pin 행 — popover.jsx L91, L443
        static let clipRow:         CGFloat = 12
        // 환경설정 행 — popover.jsx L491
        static let preferencesRow:  CGFloat = 8
        // 키캡 — popover.jsx L42
        static let keycap:          CGFloat = 3.5
        // Pin Row 우측 단축키 안내 키캡 — TASK-019
        static let pinRowKeycap:    CGFloat = 4
        // 검색 box — popover.jsx L341
        static let searchBox:       CGFloat = 10
        // Pin Sidebar 항목 — popover.jsx L583
        static let pinSidebarItem:  CGFloat = 10
        // 빈 상태 round 컨테이너 — popover.jsx L390
        static let emptyContainer:  CGFloat = 22

        // Settings — settings.jsx L444 (윈도우 12) + L495 (탭 8)
        static let settingsWindow:  CGFloat = 12
        static let settingsTab:     CGFloat = 8
        static let settingsCard:    CGFloat = 8
        static let settingsButton:  CGFloat = 5

        // Toast — onboarding-toast.jsx L228
        static let toast:           CGFloat = 12
        // Toast 배지 — borderRadius 9 (size 18)
        static let toastBadge:      CGFloat = 9

        // Onboarding — onboarding-toast.jsx L24 (16) + L153 cards (10)
        static let onboardingWindow: CGFloat = 16
        static let onboardingCard:   CGFloat = 10
        static let onboardingIconLg: CGFloat = 24

        // 시스템 표준
        static let xs:  CGFloat = 3
        static let sm:  CGFloat = 5
        static let md:  CGFloat = 6
        static let lg:  CGFloat = 8
        static let xl:  CGFloat = 10
        static let xxl: CGFloat = 12
    }

    // MARK: - WindowSize
    enum WindowSize {
        // popover
        static let popoverWidth:        CGFloat = 380
        static let popoverHeight:       CGFloat = 520  // 1·2·3 통합 단일 height (TASK-018) — Method1=520·Method2=320·Method3=480 통합
        static let popoverInsetBottom:  CGFloat = 28  // 방식 2/3 우하단 inset
        static let popoverInsetRight:   CGFloat = 28
        // 312 → 276 (TASK-018 Phase 4) — single-line 행(44) + rowGap(2) × 6행 - 마지막 gap(2) = 274 + 행 외곽 2px 여유. Pin 행이 잘린 마지막 행을 가리던 현상 제거.
        static let clipListMaxHeight:   CGFloat = 276

        // Pin Sidebar
        static let pinSidebarWidth:     CGFloat = 220

        // Settings
        static let settingsWidth:       CGFloat = 620
        static let settingsHeight:      CGFloat = 572  // 42 titlebar + 50 tabbar + 480 content
        static let settingsContentMaxH: CGFloat = 480

        // Onboarding
        static let onboardingWidth:     CGFloat = 480

        // Toast
        static let toastMinWidth:       CGFloat = 260
        static let toastMaxWidth:       CGFloat = 360
        static let toastInsetTop:       CGFloat = 38
        static let toastInsetRight:     CGFloat = 20

        // 키캡 최소
        static let keycapMin:           CGFloat = 14
        // 클립 행 시간 메타 width
        static let timeMetaWidth:       CGFloat = 48
        // 클립 행 typeIcon area
        static let clipTypeIconArea:    CGFloat = 16
        // image 클립 thumbnail
        static let clipImageThumbW:     CGFloat = 36
        static let clipImageThumbH:     CGFloat = 32
        // 클립 행 우측 액션 (Pin/X)
        static let clipActionSize:      CGFloat = 18
    }

    // MARK: - Shadow
    enum Shadow {
        // popover (라이트·다크 페어)
        static let popoverColor    = Color(red: 0, green: 0, blue: 0, opacity: 0.30)
        static let popoverColorDark = Color(red: 0, green: 0, blue: 0, opacity: 0.55)
        static let popoverRadius:  CGFloat = 35   // CSS 70px blur → SwiftUI radius 절반 근사
        static let popoverOffsetY: CGFloat = 22

        // popover inset 보더 highlight
        static let popoverInsetHighlight     = Color(red: 1, green: 1, blue: 1, opacity: 0.60)
        static let popoverInsetHighlightDark = Color(red: 1, green: 1, blue: 1, opacity: 0.08)
        // popover outer stroke
        static let popoverOuterStroke     = Color(red: 0, green: 0, blue: 0, opacity: 0.10)
        static let popoverOuterStrokeDark = Color(red: 0, green: 0, blue: 0, opacity: 0.50)

        // Toast
        static let toastShadow: Color = Color(red: 0, green: 0, blue: 0, opacity: 0.25)
        static let toastRadius: CGFloat = 18
        static let toastOffsetY: CGFloat = 12

        // Settings 윈도우
        static let settingsShadow: Color = Color(red: 0, green: 0, blue: 0, opacity: 0.35)
        static let settingsRadius: CGFloat = 30
        static let settingsOffsetY: CGFloat = 24

        // Onboarding
        static let onboardingShadow: Color = Color(red: 0, green: 0, blue: 0, opacity: 0.45)
        static let onboardingRadius: CGFloat = 40
        static let onboardingOffsetY: CGFloat = 30
    }

    // MARK: - Animation (Stash - Interactive Prototype.html L30-41 + store.jsx 정합)
    enum Animation {
        // Pin 사이드 펼침 — popover.jsx L424-438 / HTML L30-33
        static let pinSidebarHoverOpenDelay: TimeInterval = 0.20  // 200ms (HANDOFF §4-4 정합 — 코드 150ms 와 다름, plan 채택)
        static let pinSidebarHoverCloseDelay: TimeInterval = 0.20  // 200ms
        static let pinSidebarSlideDuration: TimeInterval = 0.18    // 180ms cubic-bezier(0.2, 0.7, 0.3, 1)

        // paste 직후 초록 플래시 — store.jsx L201-204
        static let pasteFlashDuration: TimeInterval = 0.7  // 700ms
        static let popoverAutoCloseAfterPaste: TimeInterval = 0.15  // 150ms (popover.jsx L263)

        // popover fade
        static let popoverFadeIn: TimeInterval = 0.18
        static let popoverFadeOut: TimeInterval = 0.12

        // 키보드 nav 시 ScrollView가 selected 행을 anchor: .center로 follow하는 duration
        static let scrollFollowDuration: TimeInterval = 0.10

        // 클립 행 selection / flash 그라데이션 fade — popover.jsx L344 transition: "all 0.12s"
        static let clipRowSelectionFade: TimeInterval = 0.12

        // popover dismiss 후 destination 앱 활성화 안정 대기 — NSRunningApplication.activate가 비동기 frontmost 전환을 유발해 ⌘V CGEvent가 새 frontmost에 도달할 시간 필요
        static let appActivationDelay: TimeInterval = 0.05  // 50ms

        // popover 열림 직후 짧은 시간 hover 무시 — 마우스가 검색바/클립 위에 이미 있어도 자동 활성 차단 (TASK-016 D-3).
        static let popoverOpenHoverIgnoreDelay: TimeInterval = 0.2  // 200ms

        // Toast TTL
        static let toastTTLDefault: TimeInterval = 3.0
        static let toastTTLShort:   TimeInterval = 1.8   // paste 확정
        static let toastTTLMid:     TimeInterval = 2.2   // 전체 삭제 / 단축키 충돌
        static let toastTTLPermission: TimeInterval = 2.5  // 권한 부여 / Pin 한도
        static let toastTTLLong:    TimeInterval = 3.5   // onboarding 완료

        // Onboarding modal fade-in — HTML L34-37
        static let onboardingFadeIn: TimeInterval = 0.2

        // Toast slide-in — HTML L38-41
        static let toastSlideIn: TimeInterval = 0.25
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
