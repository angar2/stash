// stash 디자인 토큰 — Claude Design 산출 (Interactive Prototype.html + popover.jsx + settings.jsx + onboarding-toast.jsx + icons.jsx + colors_and_type.css) 100% 정합
// 라이트·다크 페어는 Color(light:dark:) 헬퍼로 시스템 외관 자동 추종 (UX-UI §12-4 시각 = 디자인 우선 정합)
// Liquid Glass + 14~25 Material fallback 분기는 VisualEffectView wrapper에서 처리
import SwiftUI
import AppKit

// TASK-053 — 앱 강조 색상 모드. UX-UI §4-3 *콘텐츠 색상* 라디오 분기. UserDefaults 영속.
enum AccentColorMode: String {
    /// stash 자체 파란 `#0D6FFF` — 디폴트.
    case `default`
    /// SwiftUI `Color.accentColor` — macOS 시스템 환경설정 > 일반 > 강조 색상 추종.
    case system

    static let userDefaultsKey: String = "accentColorMode"

    /// UserDefaults 조회 — 키 없음/잘못된 값 → `.default`.
    static var current: AccentColorMode {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = AccentColorMode(rawValue: raw) else {
            return .default
        }
        return mode
    }
}

enum DesignTokens {

    // MARK: - Colors
    enum Colors {
        // ─── 앱 강조 색상 (TASK-053) ──────────────────────────────────
        /// stash 자체 파란 `#0D6FFF` 기본값. `AccentColorMode` 분기 진실 소스 (디폴트 모드 base).
        static let defaultAccent = Color(red: 13/255, green: 111/255, blue: 255/255)  // #0D6FFF (popover.jsx L11)
        /// 앱 강조 색상 — UserDefaults `accentColorMode` 분기.
        /// - `.default` → `defaultAccent` (stash 자체 파란 `#0D6FFF`).
        /// - `.system` → `Color(nsColor: NSColor.controlAccentColor)` — macOS 시스템 환경설정 > 일반 > 강조 색상 직접 추종.
        /// `Color.accentColor` 는 `Assets.xcassets/AccentColor.colorset` 의 *Asset 파란* 을 반환해 시스템 추종 X → AppKit `NSColor.controlAccentColor` 를 직접 wrap (TASK-053 root cause).
        /// computed property — 호출 시점 UserDefaults 조회. View body 재평가 시점에 새 값 반영.
        static var accent: Color {
            switch AccentColorMode.current {
            case .default: return defaultAccent
            case .system: return Color(nsColor: NSColor.controlAccentColor)
            }
        }
        static let accentForeground = Color.white
        // TASK-035 — 검색 매칭 텍스트 전경 (UX-UI §7-3). accent 별칭으로 의미 분리 — 향후 매칭 색상만 별도 조정 가능.
        static var searchMatchForeground: Color { accent }
        // 보라 톤 보조 색상 (TASK-069 이전 적층 카드 + WelcomeStep 그라데이션 보조 — 폐기 후 ClipDetailProvider.swift:380 이미지 fallback 톤만 잔존). TASK-053 비대상. 후속 task 에서 imagePlaceholderAccent 등으로 리네임 검토.
        static let appIconAccent = Color(red: 100/255, green: 50/255, blue: 200/255)
        static let primaryButtonStart = Color(red: 45/255, green: 134/255, blue: 245/255)  // 그라데이션 상단

        // ─── popover / sidebar 배경 (Liquid Glass over blur 50 + sat 200%) — popover.jsx L280-292 ───
        static let popoverBackground = Color(
            light: Color(red: 248/255, green: 247/255, blue: 250/255, opacity: 0.72),
            dark:  Color(red: 28/255,  green: 26/255,  blue: 38/255,  opacity: 0.62)
        )

        // ─── 클립 행 선택 그라데이션 (linear-gradient 180deg) — popover.jsx L52-58 ───
        // TASK-053 fix-5 — 라이트/다크 모두 accent 베이스 + 런타임 opacity 곱 (모드 분기 자동 추종, 다크 모드도 시스템 강조 색상 추종).
        static var clipRowSelectionTop: Color {
            Color(
                light: accent.opacity(0.14),
                dark:  accent.opacity(0.32)
            )
        }
        static var clipRowSelectionBottom: Color {
            Color(
                light: accent.opacity(0.10),
                dark:  accent.opacity(0.32)
            )
        }
        // 선택 행 inset 보더
        static var clipRowSelectionBorder: Color {
            Color(
                light: accent.opacity(0.22),
                dark:  accent.opacity(0.35)
            )
        }

        // ─── 다중 선택 (TASK-099) ────────────────────────────────────
        // 커서 행(회색 그라데이션)과 *동시에* 걸릴 수 있어, 선택 상태가 커서보다 진하게 읽혀야 한다.
        // 커서 행 선택 그라데이션과 같은 accent 베이스를 쓰되 배경은 한 톤 옅게 깔고 테두리로 경계를 준다.
        static var multiSelectRowBackground: Color {
            Color(
                light: accent.opacity(0.10),
                dark:  accent.opacity(0.20)
            )
        }
        static var multiSelectRowBorder: Color {
            Color(
                light: accent.opacity(0.40),
                dark:  accent.opacity(0.50)
            )
        }
        /// 선택 순서 칩 배경 — 행 위에 겹쳐 뜨므로 배경과 대비가 확실해야 한다.
        static var multiSelectChipBackground: Color { accent }
        static let multiSelectChipForeground = Color.white
        // 칩 둘레의 링(`multiSelectChipRing`)은 폐기했다 — 다크에서 검은 외곽선처럼 읽혔다(사용자 검수).
        // 개수 배지를 아이콘 우하단으로 옮겨 대각으로 떨어뜨렸으므로 링 없이도 서로 구분된다.
        // ─── 프리뷰 바 (TASK-099, 검수 fix-3 개정) ───────────────────
        // 초안은 바탕·보더·라벨·연결자가 전부 accent 계열이라 파란색이 네 겹으로 겹쳐 산만했다(사용자 검수).
        // 바탕을 **검색바와 같은 어두운 톤** 으로 내리고, accent 는 *내용 칩* 하나에만 남긴다.
        static let previewBarBackground = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 0, green: 0, blue: 0, opacity: 0.28)
        )
        static let previewBarBorder = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.10),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.09)
        )
        /// 클립 하나를 담는 칩. 프리뷰에서 **유일하게** 강조 색을 쓰는 자리다.
        static var previewChipBackground: Color {
            Color(
                light: accent.opacity(0.14),
                dark:  accent.opacity(0.22)
            )
        }
        static var previewChipBorder: Color {
            Color(
                light: accent.opacity(0.40),
                dark:  accent.opacity(0.55)
            )
        }
        static var previewChipForeground: Color {
            Color(
                light: accent.opacity(0.95),
                dark:  Color(red: 207/255, green: 228/255, blue: 1, opacity: 1)
            )
        }
        // 파일·이미지 칩은 **키캡과 같은 회색 톤** 을 쓴다 (검수 결정).
        // 텍스트는 이어붙여 하나가 되고 파일은 배열로 따로 붙는데, 색이 같으면 그 차이가 안 보인다.
        // 키캡 토큰을 그대로 참조해 힌트바·설정 코드 칩과 한 계열로 묶는다.
        static var previewFileChipBackground: Color { keycapBg }
        static var previewFileChipBorder: Color { keycapInset }
        static var previewFileChipForeground: Color { keycapFg }

        // ─── 업데이트 배너 (TASK-102) ──────────────────────────────
        // 프리뷰 바가 *어두운* 바탕을 쓰므로 배너는 강조 톤 바탕 한 겹으로 간다 — 둘이 동시에 떠도 구분된다.
        static var updateBannerBackground: Color {
            Color(
                light: accent.opacity(0.10),
                dark:  accent.opacity(0.16)
            )
        }
        static var updateBannerBorder: Color {
            Color(
                light: accent.opacity(0.32),
                dark:  accent.opacity(0.42)
            )
        }
        /// 배너 위 마우스 — 배너 전체가 눌리는 영역이라는 단서.
        static var updateBannerBackgroundHover: Color {
            Color(
                light: accent.opacity(0.17),
                dark:  accent.opacity(0.24)
            )
        }
        /// 버전 번호 강조. 배너에서 가장 먼저 읽혀야 하는 정보다.
        static var updateBannerVersionForeground: Color {
            Color(
                light: accent.opacity(0.95),
                dark:  Color(red: 207/255, green: 228/255, blue: 1, opacity: 1)
            )
        }

        /// 설정 화면 텍스트 입력란 (TASK-099 연결자). 단축키 Recorder 와 같은 톤을 쓴다 —
        /// 같은 탭 안에서 *값을 넣는 자리* 라는 인상이 어긋나지 않도록.
        static let inputFieldBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)
        static let inputFieldBorder = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.18),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.18)
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

        // TASK-061 — 빈 상태 색 토큰 (`emptyTitleColor` / `emptyHintColor`) 폐기. emptyState view 폐기로 사용처 0.
        // TASK-037 — 빈 상태 트레이 아이콘 / 라운드 컨테이너 색 토큰 폐기 (빈 상태 UI 단순화 — 멘트 only).

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
        // searchFocused 시 보더 (파란 라인) — TASK-053 accent 베이스 추종.
        static var searchBoxFocusedBorder: Color { accent.opacity(0.50) }
        // 검색 아이콘 (비활성)
        static let searchIconInactive = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.45),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.50)
        )

        // TASK-068 — popover 상단 액션 버튼 (일시정지·잠금 토글 등) hover bg. 라이트=어두운 hover (`keycapBg` 라이트 톤 정합) / 다크=밝은 hover (기존 hard-code 톤 유지). 라이트 모드 검색바 위 흰색 hover 가 시각 피드백 실종되던 회귀 fix.
        static let popoverActionButtonHoverBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.05)
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
        // TASK-068 — pinRowKeycapBg 토큰 폐기. 핀 행 ⌘B / 환경설정 행 ⌘, 키캡 배경을 표준 힌트바 키캡 `keycapBg` 와 통합 (라이트 모드 시각 정합).

        // ─── 환경설정 행 색 ──────────────────────────────────────────
        static let preferencesRow = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.50),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.60)
        )

        // ─── 클립 행 액션 (Pin/X 버튼) ───────────────────────────────
        // 선택된 행의 X 버튼 bg — TASK-053 fix-5 라이트/다크 모두 accent 베이스 추종.
        static var clipDeleteBg: Color {
            Color(
                light: accent.opacity(0.10),
                dark:  accent.opacity(0.22)
            )
        }
        /// X 버튼 hover 시 배경 — baseline opacity 0.10 → 0.22 (시각 피드백).
        static var clipDeleteBgHover: Color {
            Color(
                light: accent.opacity(0.22),
                dark:  accent.opacity(0.38)
            )
        }
        // 선택된 행의 X 아이콘 — TASK-053 fix-2. 라이트 모드는 비선택 아이콘과 동일 회색 톤 고정 (커서 이동 시 색상 변경 X). 다크 모드는 기존 흰 강조 유지 (별도 task 정합).
        static var clipDeleteIcon: Color {
            Color(
                light: Color(red: 0, green: 0, blue: 0, opacity: 0.45),
                dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
            )
        }
        // 선택된 행의 typeIcon — TASK-053 fix-2. 라이트 모드는 비선택과 동일 회색 톤 고정. 다크 모드는 기존 흰 강조 유지.
        static var clipTypeIconSelected: Color {
            Color(
                light: Color(red: 0, green: 0, blue: 0, opacity: 0.45),
                dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.85)
            )
        }
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

        // ─── 수집 토글 indicator (TASK-043) ──────────────────────────
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
        // TASK-024 — 비활성 키캡 (⌘V 권한 게이트 시각). 기본 키캡 opacity 의 약 1/3 수준으로 회색조 표시.
        static let keycapBgDisabled = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.03),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.05)
        )
        static let keycapFgDisabled = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.22),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.27)
        )
        static let keycapInsetDisabled = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.025),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.025)
        )
        // 힌트 라벨
        static let hintLabel = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.42),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.45)
        )
        // TASK-024 — 비활성 힌트 라벨 (⌘V 권한 게이트 시각).
        static let hintLabelDisabled = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.18),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.20)
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
        /// TASK-065 — 설정 윈도우 카드형 버튼 hover 배경. 라이트=옅은 그레이 / 다크=더 밝게.
        static let settingsCardBgHover = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.06),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.10)
        )
        /// TASK-098 — PIN 단축키 행 인라인 인풋(명칭·값 공통) 배경. 다크는 승인 목업 톤 그대로,
        /// 라이트는 같은 *들어간 느낌* 을 옅은 음영으로 만든다 — 다크 값(검정 24%)을 라이트에 그대로 쓰면
        /// 밝은 배경 위에 탁한 회색 박스가 얹힌다.
        static let settingsInputBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.045),
            dark:  Color(red: 0, green: 0, blue: 0, opacity: 0.24)
        )
        /// TASK-098 — 저장/취소 원형 버튼 기본 배경 (hover 시엔 각 버튼 tint 를 얹는다).
        /// 라이트에서 흰색 오버레이는 흰 카드에 묻혀 버튼 자체가 사라지므로 방향을 뒤집는다.
        static let settingsCircleButtonBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.045),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.06)
        )
        /// TASK-098 — Pin 사이드바 조합 키캡 배경 (다크 = 목업 `--keycap-bg` 그대로).
        static let pinKeycapBg = Color(
            light: Color(red: 0, green: 0, blue: 0, opacity: 0.055),
            dark:  Color(red: 1, green: 1, blue: 1, opacity: 0.10)
        )
        /// TASK-098 — PIN 단축키 행 편집 *핀 해제* 원형 버튼 tint. 저장(초록)·취소(보조 색)와 구분되는 경고 톤.
        /// 항목이 사라지지 않는 동작(히스토리에 남고 값 수정분도 유지 — 초기화되는 건 명칭뿐)이라
        /// 삭제용 빨강(`255,56,60`)보다 한 단계 낮은 주황을 쓴다.
        static let pinUnpinButton = Color(
            light: Color(red: 199/255, green: 105/255, blue: 0/255,   opacity: 1.0),
            dark:  Color(red: 255/255, green: 175/255, blue: 82/255,  opacity: 1.0)
        )
        /// TASK-098 — PIN 단축키 행 편집 *저장* 원형 버튼 tint (취소는 `labelSecondary` 재사용).
        /// accent(파랑)를 쓰지 않는 이유 — 같은 행의 조합 입력 focus 강조가 accent 라 저장 버튼과 시각적으로 구분되지 않는다.
        static let pinSaveButton = Color(
            light: Color(red: 26/255,  green: 143/255, blue: 87/255,  opacity: 1.0),
            dark:  Color(red: 126/255, green: 226/255, blue: 168/255, opacity: 1.0)
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

        // Toggle / Radio — TASK-053 accent 추종 (var 로 변환 — accent 분기 시 자동 갱신).
        static var toggleOnBg: Color { accent }
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

        // TASK-079 — 호버 툴팁 시각. popover `nonactivatingPanel` + `becomesKeyOnlyIfNeeded=true` 환경에서 NSToolTip(SwiftUI `.help()` backing) 미발화 → SwiftUI `.overlay` 자체 구현. macOS 시스템 NSToolTip 시각 흉내.
        /// 호버 툴팁 배경 — 시스템 라이트·다크 자동 적응. 살짝 반투명 (NSToolTip 정합).
        static let tooltipBg = Color(
            light: Color(red: 252/255, green: 252/255, blue: 252/255, opacity: 0.96),
            dark:  Color(red: 50/255,  green: 50/255,  blue: 52/255,  opacity: 0.96)
        )
        /// 호버 툴팁 테두리 — `NSColor.separatorColor` 정합.
        static let tooltipBorder = Color(nsColor: NSColor.separatorColor)
        /// 호버 툴팁 라벨 — `NSColor.labelColor` 정합 (라이트·다크 자동).
        static let tooltipLabel = Color(nsColor: NSColor.labelColor)
    }

    // Toast kind enum (DesignTokens 내부용 — UI 파일에선 별도 ToastKind 사용)
    enum ToastKindToken {
        case success, info, warn, error
    }

    // MARK: - Typography (popover.jsx + settings.jsx + onboarding-toast.jsx 정합)
    enum Typography {
        // 워드마크 "Stash" — popover.jsx L321-326
        static let brandWordmark   = Font.system(size: 13, weight: .heavy).leading(.tight)
        // 클립 본문 (text)
        static let clipBody        = Font.system(size: 13, weight: .medium)
        // 클립 본문 (mono — code-like)
        static let clipBodyMono    = Font.system(size: 12.5, weight: .medium, design: .monospaced)
        // 행 헤더 (핀 목록 / 환경설정)
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
        // TASK-061 — `emptyTitle` / `emptyHint` Font 토큰 폐기. emptyState view 폐기로 사용처 0.

        // Pin Sidebar 헤더 (UPPERCASE tracking 0.08em)
        static let pinSidebarHeader = Font.system(size: 10, weight: .heavy)

        // Clip Detail 메타 footer + 복사 위치 라인 (TASK-039)
        static let clipMetaApp           = Font.system(size: 11.5, weight: .medium)
        static let clipMetaTime          = Font.system(size: 10.5, weight: .regular).monospacedDigit()
        static let clipMetaLocationLabel = Font.system(size: 10, weight: .regular)
        static let clipMetaLocationPath  = Font.system(size: 11, weight: .regular, design: .monospaced)
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

        // TASK-079 — 호버 툴팁 본문 폰트. macOS 시스템 NSToolTip ~11pt regular 정합.
        static let tooltip = Font.system(size: 11, weight: .regular)
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
        // TASK-080 — popoverBody 마지막 자식 ↔ popover 외곽 추가 outer bottom spacing. rowOuterHorzInset(6) 좌우 outer 패턴과 정합 (값 동일 6pt). 자식 자체 padding 손대지 X — background 두께 변경 0. hintBar ON/OFF 양쪽 케이스 동시 시각 대칭 (ON: 좌우 16=하단 6+4+6=16 / OFF: 좌우 12=하단 6+6=12).
        static let popoverPaddingBottomExtra: CGFloat = 6
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
        // TASK-037 — 행 단일 고정 높이 정책. rowPaddingMultiV (multi-line 가변 padding) 폐기.
        static let rowMinHeight:           CGFloat = 44
        static let rowPaddingSingleH:      CGFloat = 12  // 단일줄 vertical 0
        static let rowPaddingMultiH:       CGFloat = 12
        static let rowGap:                 CGFloat = 2
        static let rowInnerGap:            CGFloat = 10
        static let rowTrailingGap:         CGFloat = 8

        // Pin 행 (popover.jsx L423-467)
        static let pinRowHeight:           CGFloat = 38
        static let pinRowPaddingHorz:      CGFloat = 12
        static let pinRowMarginVert:       CGFloat = 2

        // 환경설정 행 (popover.jsx L470-497)
        static let preferencesRowPadHorz:  CGFloat = 12

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
        // Pin sidebar 동적 height 계산 상수 (TASK-019 fix 2차 ~ 6차 / TASK-048 정정 — `PopoverWindow.computePinSidebarHeight`)
        // maxPinnedClips=10 하드 캡 전제. 10 pins exact fit (popoverHeight=520 - bottomMargin=18 = 502 = header+padding+rows+gaps).
        static let pinSidebarHeaderHeight: CGFloat = 32  // 헤더 ("핀 목록 · N") 영역 height
        static let pinSidebarHeightBottomMargin: CGFloat = 18  // popoverHeight 와의 상단 갭 (사이드바 top 가 popover top 보다 18px 아래)

        // 단축키 키캡 (Pin Row 우측 `⌘B` 안내 등 — TASK-019)
        static let keycapPaddingHorz:      CGFloat = 5
        static let keycapPaddingVert:      CGFloat = 1
        static let keycapStrokeWidth:      CGFloat = 0.5

        // TASK-061 — 빈 상태 padding 토큰 (`emptyPaddingTop` / `emptyPaddingBottom` / `emptyPaddingHorz` / `emptyTitleToHint`) 폐기. emptyState view 폐기로 사용처 0.

        // TASK-037 — 디스플레이 환경설정 / popover 동적 frame 토큰.
        // clipListOverheadBase = clipList 외 SwiftUI body 영역 (검색바 + 환설정 행 + 힌트바 + popoverPadding × 2) 측정값.
        // hasPinned 시 pinRow + margin 추가됨 (ClipsViewModel.effectiveClipListHeight 안 동적 합산).
        static let clipListOverheadBase:   CGFloat = 164
        // TASK-052 — 힌트바 영역 (Divider + FlowLayout + padding) 동적 가감 토큰. 실측 42pt (ON 1410 - OFF 1368). hintBar OFF 시 totalOverhead 에서 차감해 clipList cap 확장 → clipList 가 한 행 더 표시 + popover total height ON/OFF 동일 유지 (method2 우하단 anchor 시 상단 공백 잔존 차단).
        // TASK-056 — NSPanel 실측 (popover open log) ON - OFF fitting.height 차이 34pt. 기존 42pt 추정값 폐기, 실측 34pt 박음.
        static let hintBarOverhead:        CGFloat = 34

        // TASK-099 — 다중 선택 프리뷰 바.
        // 실제 높이는 본문 줄 수(1~3)와 혼합 안내 유무로 달라지며, popover 높이는 SwiftUI fittingSize 가 따라간다.
        // 아래 `previewBarOverhead` 는 *화면 cap 계산* 에만 쓰는 보수적 추정치다 — 바가 떠 있는 동안
        // 클립 목록 상한을 그만큼 낮춰, 선택 중에 popover 가 화면 밖으로 자라는 것을 막는다.
        static let previewBarPaddingHorz:  CGFloat = 9
        static let previewBarPaddingVert:  CGFloat = 6
        static let previewBarBottomGap:    CGFloat = 6
        static let previewBarMaxLines:     Int = 3
        static let previewBarOverhead:     CGFloat = 62
        /// 칩 사이 간격 (가로·세로 공통). 검수 fix-3 — 칩 구조 전환.
        static let previewChipGap:         CGFloat = 4
        /// 칩 하나의 최대 너비. 긴 본문이 바를 세로로 부풀리지 않도록 여기서 말줄임한다.
        static let previewChipMaxWidth:    CGFloat = 150

        // TASK-102 — 업데이트 배너 (헤더 안, 로고 행 아래·검색부 위).
        // 프리뷰 바와 달리 본문이 한 줄 고정(버전 문구)이라 높이가 변하지 않는다.
        static let updateBannerHeight:      CGFloat = 30
        static let updateBannerPaddingHorz: CGFloat = 9
        /// 위아래 이웃과의 간격을 **둘 다 8pt** 로 맞춘다 (검수 2026-08-02 — 처음엔 위가 붙고, 고친 뒤엔 아래가 벌어졌다).
        /// 이웃이 이미 자기 여백을 갖고 있어 배너가 더하는 값은 서로 다르다:
        ///   위 = `wordmarkPaddingBottom`(2) + 여기 6 = 8
        ///   아래 = 여기 4 + `searchContainerPaddingTop`(4) = 8
        static let updateBannerTopGap:      CGFloat = 6
        static let updateBannerBottomGap:   CGFloat = 4
        /// 화면 cap 계산용 — 배너가 떠 있는 동안 클립 목록 상한을 그만큼 낮춰 popover 가 화면 밖으로 자라는 것을 막는다.
        /// 높이(30) + 위 간격(6) + 아래 간격(4).
        static let updateBannerOverhead:    CGFloat = 40

        // 디스플레이 탭 슬라이더 최대 너비.
        static let displaySliderMaxWidth:  CGFloat = 240

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
        static let toastBadgeSize:         CGFloat = 18  // X 닫기 버튼 사이즈 (TASK-066 — 로고와 분리)
        static let toastLogoSize:          CGFloat = 18  // TASK-066 — 좌측 stash 로고 사이즈 (X 닫기와 통일). TASK-069 — MenuBarIcon template 사용 + kind 색상 fill.
        static let toastStackGap:          CGFloat = 8
        static let toastWindowPadding:     CGFloat = 8

        // Clip Detail sub-window (TASK-027) — 다중파일 상세 sub-window 외피·꼭지·행 spacing
        static let clipDetailGap:          CGFloat = 2   // popover/PinSidebar 좌측 간격 — 꼭지 끝과 본체 윈도우 사이 거리 (TASK-039 fix: 20 → 2, 사용자 시각 검수 — 본체와 더 가깝게 붙도록)
        static let clipDetailArrowWidth:   CGFloat = 8   // 꼭지(말풍선 화살표) 가로 — 우측 가장자리에서 튀어나옴
        static let clipDetailArrowHeight:  CGFloat = 14  // 꼭지 세로
        static let clipDetailRowHeight:    CGFloat = 28  // 파일 목록 단일 행 height
        static let clipDetailRowInnerGap:  CGFloat = 6   // 파일 행 안 아이콘 ↔ 라벨 사이 간격
        static let clipDetailRowPadH:      CGFloat = 8   // 파일 행 내부 좌우 padding
        static let clipDetailRowIconSize:  CGFloat = 11  // 파일 행 doc 아이콘 size
        static let clipDetailPadding:      CGFloat = 16  // panel 내부 outer padding (본문 ScrollView 외곽 — TASK-039 fix: 8 → 12 → 16)
        static let clipDetailEdgeSafety:   CGFloat = 8   // 화면 좌/상/하단 경계 safe margin
        /// 활성 행 frame 변동 *유의미한 변화* 임계값 (TASK-027). 1pt 미만 미세 변동은 무시 — Geometry update 폭주 차단.
        static let clipDetailFrameDeltaThreshold: CGFloat = 1

        // Clip Detail sub-window 메타 footer + 복사 위치 라인 (TASK-039) — 4 종 ClipType 공통 하단 영역
        static let clipMetaFooterHeight:        CGFloat = 36  // 출처 앱 + 시간 표시 1줄 footer height (TASK-039 fix4: 28 → 36)
        static let clipMetaIconSize:            CGFloat = 14  // 출처 앱 아이콘 size — 텍스트 글자 높이 정합
        static let clipMetaHGap:                CGFloat = 6   // 메타 footer 안 horizontal 간격
        static let clipMetaPadH:                CGFloat = 16  // 메타 footer / 복사 위치 라인 좌우 padding (clipDetailPadding 정합 — TASK-039 fix3: 12 → 16)
        static let clipMetaPadV:                CGFloat = 10  // 메타 footer 상하 padding (TASK-039 fix4: 6 → 10)
        static let clipMetaLocationBlockHeight: CGFloat = 44  // 복사 위치 라인 (라벨 + 경로) 블록 height (TASK-039 fix4: 36 → 44)

        // TASK-079 — 호버 툴팁 spacing. macOS NSToolTip 시각 흉내.
        static let tooltipPaddingH: CGFloat = 8
        static let tooltipPaddingV: CGFloat = 4
        /// `.topTrailing` alignment 기준 — overlay top edge 위치 = content top + offsetY. 버튼 height 16 + gap 6 = 22pt.
        /// 버튼 (16pt) 을 완전히 아래로 비켜 박음 — overlay 가 버튼 영역을 가리지 X.
        static let tooltipOffsetY:  CGFloat = 22
    }

    // MARK: - Radius
    enum Radius {
        // popover / sidebar 외곽 — popover.jsx L283
        static let popoverOuter:    CGFloat = 18
        // 클립 행 / Pin 행 / 환경설정 행 — popover.jsx L91, L443, L491 (TASK-067 — preferencesRow 토큰 폐기, 단일 clipRow 통합)
        static let clipRow:         CGFloat = 12
        // 키캡 — popover.jsx L42
        static let keycap:          CGFloat = 3.5
        // Pin Row 우측 단축키 안내 키캡 — TASK-019
        static let pinRowKeycap:    CGFloat = 4
        // 검색 box — popover.jsx L341
        static let searchBox:       CGFloat = 10
        // Pin Sidebar 항목 — popover.jsx L583
        static let pinSidebarItem:  CGFloat = 10
        // TASK-037 — 빈 상태 round 컨테이너 Radius 토큰 폐기 (빈 상태 UI 단순화).

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

        // TASK-079 — 호버 툴팁 corner radius. macOS NSToolTip ~4pt 정합.
        static let tooltip: CGFloat = 4
    }

    // MARK: - WindowSize
    enum WindowSize {
        // popover
        static let popoverWidth:        CGFloat = 380
        static let popoverHeight:       CGFloat = 520  // 1·2·3 통합 단일 height (TASK-018) — Method1=520·Method2=320·Method3=480 통합
        static let popoverInsetBottom:  CGFloat = 0  // 방식 2/3 우하단 inset (bottom) — 사용자 의도: 완전 붙음
        static let popoverInsetRight:   CGFloat = 0  // 방식 2/3 우측 inset
        // 312 → 276 (TASK-018 Phase 4) — single-line 행(44) + rowGap(2) × 6행 - 마지막 gap(2) = 274 + 행 외곽 2px 여유. Pin 행이 잘린 마지막 행을 가리던 현상 제거.
        static let clipListMaxHeight:   CGFloat = 276

        // Pin Sidebar
        static let pinSidebarWidth:     CGFloat = 220

        // Clip Detail sub-window (TASK-027) — 다중파일 상세 sub-window panel 크기
        static let clipDetailWidth:     CGFloat = 240
        static let clipDetailMaxHeight: CGFloat = 440  // popoverHeight(520) - 80 safety

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
        // TASK-068 — popover 그림자는 `PopoverPanel.swift:101` `p.hasShadow = true` NSPanel OS 기본 그림자 사용. 색·수치 토큰 7종 (`popoverColor`/`popoverColorDark`/`popoverRadius`/`popoverOffsetY`/`popoverInsetHighlight`/`popoverInsetHighlightDark`/`popoverOuterStrokeDark`) 호출처 0건 dead code → 폐기. `popoverOuterStroke` 만 유지 (라이트용, `HistoryPopover.swift:95` 호출 1건. 다크 모드 시각 위화감 검수 결과 = 없음 → 다크용 별도 토큰 불필요).
        static let popoverOuterStroke = Color(red: 0, green: 0, blue: 0, opacity: 0.10)

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

        // Clip Detail sub-window (TASK-027) — 다중파일 상세 sub-window debounce
        static let clipDetailDebounceDelay: TimeInterval = 0.20  // 200ms (pinSidebar hover 정합)

        // popover fade
        static let popoverFadeIn: TimeInterval = 0.18
        static let popoverFadeOut: TimeInterval = 0.12

        // 키보드 nav 시 ScrollView가 selected 행을 anchor: .center로 follow하는 duration
        static let scrollFollowDuration: TimeInterval = 0.10

        // 클립 행 selection 그라데이션 fade — popover.jsx L344 transition: "all 0.12s"
        static let clipRowSelectionFade: TimeInterval = 0.12

        // popover dismiss 후 destination 앱 활성화 안정 대기 — NSRunningApplication.activate가 비동기 frontmost 전환을 유발해 ⌘V CGEvent가 새 frontmost에 도달할 시간 필요
        static let appActivationDelay: TimeInterval = 0.05  // 50ms

        // popover 열림 직후 짧은 시간 hover 무시 — 마우스가 검색바/클립 위에 이미 있어도 자동 활성 차단 (TASK-016 D-3).
        static let popoverOpenHoverIgnoreDelay: TimeInterval = 0.2  // 200ms

        // Toast TTL (TASK-066 — kind별 통일, ToastKind.defaultTTL 단일 진실)
        static let toastTTLSuccess: TimeInterval = 2.0  // 붙여넣기/복사/수집 토글/권한 부여/전체 삭제
        static let toastTTLInfo:    TimeInterval = 2.5  // 현재 사용처 X, 미래 추가용
        static let toastTTLWarn:    TimeInterval = 3.0  // 핀 한도/다중 파일 한도/단축키 검증
        static let toastTTLError:   TimeInterval = 4.0  // 시스템 로그인 실패/다중 파일 저장 실패

        // Onboarding modal fade-in — HTML L34-37
        static let onboardingFadeIn: TimeInterval = 0.2

        // Toast slide-in — HTML L38-41
        static let toastSlideIn: TimeInterval = 0.25

        // TASK-079 — 호버 툴팁 fade in/out. clipRowSelectionFade (0.12) 정합 — popover 안 짧은 시각 전이 일관성.
        static let tooltipFade: TimeInterval = 0.12
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

// TASK-069 — 앱 아이콘(TASK-106부터 Resources/AppIcon.icon)은 Finder/Dock 용 특수 슬롯으로 컴파일돼 SwiftUI `Image("AppIcon")` 으로 로드 X. NSWorkspace 로 *.app bundle 의 아이콘 추출* 후 SwiftUI 래핑. 4 곳 (WelcomeStep/AboutTab/ToastView/SearchBarView) 에서 호출.
extension Image {
    /// stash 앱 아이콘 — Finder/Dock 에 표시되는 아이콘과 동일 시각.
    static var stashAppIcon: Image {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
    }
}
