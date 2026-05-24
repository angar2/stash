// 클립 상세 sub-window 하단 공통 메타 footer (TASK-039) — 출처 앱 (로고+이름) + 복사 시간 (YYYY-MM-DD HH:mm) 표시
// 4 종 ClipType detail (text · image · single file · multi file) 모두 동일 footer 표시 → 활성 type 간 시각 일관성 보장.
import SwiftUI
import AppKit
import OSLog

/// `ClipDetailPanelView` 가 ScrollView 밖 panel 하단에 박는 공통 메타 footer.
/// - 좌측 = 출처 앱 아이콘 (14×14) + 앱 이름 (`FileManager.displayName`).
/// - 우측 = 복사 시간 (`yyyy-MM-dd HH:mm` 절대 형식, `Locale(identifier: "en_US_POSIX")`, `TimeZone.current`).
/// - 출처 앱 nil / 미설치 → 회색 fallback 아이콘 + i18n `clipDetail.meta.unknownApp` ("알 수 없음").
struct ClipMetaFooterView: View {
    let clip: Clip
    /// TASK-073 — 언어 변경 시 body 재평가 → "알 수 없음" / Unknown 등 즉시 갱신.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    /// 시간 포맷 정확성 단일 진실. static let 1회 생성 (Foundation DateFormatter 이 macOS 15+ 부터 Sendable 부합).
    /// `Locale(identifier: "en_US_POSIX")` + `TimeZone.current` 로 로케일 무관 절대 형식 보장.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// `ClipMetaFooterFormatTests` 가 외부에서 호출하는 static 헬퍼. 시간 포맷 단위 테스트 진실 소스.
    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    var body: some View {
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return HStack(spacing: DesignTokens.Spacing.clipMetaHGap) {
            // 출처 앱 아이콘 (14×14)
            appIconView
                .frame(width: DesignTokens.Spacing.clipMetaIconSize,
                       height: DesignTokens.Spacing.clipMetaIconSize)
            // 앱 이름 (truncate)
            Text(Self.appDisplayName(for: clip.sourceAppBundleId))
                .font(DesignTokens.Typography.clipMetaApp)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DesignTokens.Spacing.clipMetaHGap)
            // 복사 시간 (tabular monospace) — TASK-045: 일시 보존 우선 정책. layoutPriority(1) + fixedSize 로 HStack 압축 단계에서 ideal width (`yyyy-MM-dd HH:mm` 16자) 우선 확보 → 잘림 X 보장. 앱이름은 잔여 폭만 점유하고 초과분 .tail truncate.
            Text(Self.formatTime(clip.createdAt))
                .font(DesignTokens.Typography.clipMetaTime)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DesignTokens.Spacing.clipMetaPadH)
        .padding(.vertical, DesignTokens.Spacing.clipMetaPadV)
        .frame(height: DesignTokens.Spacing.clipMetaFooterHeight)
        .background(
            // 상단 보더 — 본문과 시각 분리
            DesignTokens.Colors.divider
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)
        )
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = Self.appIcon(for: clip.sourceAppBundleId) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            // fallback — 회색 RoundedRectangle 그라데이션 (출처 앱 nil / 미설치)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        }
    }

    // MARK: - 앱 아이콘 / 이름 lookup (PrivacyTab 패턴 정합)

    /// 번들 ID → 앱 아이콘. `NSWorkspace.urlForApplication` → `icon(forFile:)`. nil / 미설치 → nil.
    static func appIcon(for bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 번들 ID → 앱 표시 이름 (한글 환경 = 한글 이름). nil / 미설치 → i18n `clipDetail.meta.unknownApp` ("알 수 없음").
    static func appDisplayName(for bundleId: String?) -> String {
        guard let bundleId, !bundleId.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return L10n("clipDetail.meta.unknownApp")
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}
