// Toast 행 — UX-UI §6 알림 표 진실 소스 (TASK-066)
// 4 kind (success / info / warn / error) + 좌측 14×14 stash 적층 카드 로고 (kind 색상 fill) + Liquid Glass background + 우측 18×18 X 닫기
import SwiftUI

enum ToastKind: Sendable {
    case success
    case info
    case warn
    case error

    var color: Color {
        switch self {
        case .success: return DesignTokens.Colors.toastSuccess
        case .info:    return DesignTokens.Colors.toastInfo
        case .warn:    return DesignTokens.Colors.toastWarn
        case .error:   return DesignTokens.Colors.toastError
        }
    }

    var token: DesignTokens.ToastKindToken {
        switch self {
        case .success: return .success
        case .info:    return .info
        case .warn:    return .warn
        case .error:   return .error
        }
    }

    // TASK-066 — kind별 TTL 단일 진실 소스 (DesignTokens.Animation 토큰 추종)
    var defaultTTL: TimeInterval {
        switch self {
        case .success: return DesignTokens.Animation.toastTTLSuccess
        case .info:    return DesignTokens.Animation.toastTTLInfo
        case .warn:    return DesignTokens.Animation.toastTTLWarn
        case .error:   return DesignTokens.Animation.toastTTLError
        }
    }
}

struct ToastItem: Identifiable, Sendable {
    let id: UUID = UUID()
    let kind: ToastKind
    let text: String
    let ttl: TimeInterval
}

struct ToastView: View {
    let item: ToastItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.toastGap) {
            // TASK-069 — 좌측 stash 메뉴바 아이콘 (단색 검정 template — 작은 18 px 사이즈 시인성 위해 컬러풀 AppIcon 대신 채택). TASK-066 kind 색상 fill 부활.
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .frame(width: DesignTokens.Spacing.toastLogoSize, height: DesignTokens.Spacing.toastLogoSize)
                .foregroundStyle(item.kind.color)

            Text(item.text)
                .font(DesignTokens.Typography.toastBody)
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.toastDismissColor)
            }
            .buttonStyle(.plain)
            .frame(width: DesignTokens.Spacing.toastBadgeSize, height: DesignTokens.Spacing.toastBadgeSize)
        }
        .padding(.horizontal, DesignTokens.Spacing.toastPaddingHorz)
        .padding(.vertical, DesignTokens.Spacing.toastPaddingVert)
        .frame(minWidth: DesignTokens.WindowSize.toastMinWidth, maxWidth: DesignTokens.WindowSize.toastMaxWidth, alignment: .leading)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                DesignTokens.Colors.toastBackground
                DesignTokens.Colors.toastBg(kind: item.kind.token)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.toast, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.toast, style: .continuous)
                .stroke(item.kind.color.opacity(0.50), lineWidth: 0.5)
        )
        .shadow(color: DesignTokens.Shadow.toastShadow, radius: DesignTokens.Shadow.toastRadius, y: DesignTokens.Shadow.toastOffsetY)
    }
}
