// Toast 행 — onboarding-toast.jsx L218-271 100% 정합
// 4 kind (success / info / warn / error) + 좌측 18×18 원형 아이콘 배지 + Liquid Glass background + 닫기 X
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

    var symbol: String {
        switch self {
        case .success: return "checkmark"
        case .info:    return "info"
        case .warn:    return "exclamationmark"
        case .error:   return "xmark"
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
            // 좌측 18×18 원형 배지
            ZStack {
                Circle()
                    .fill(item.kind.color)
                    .frame(width: DesignTokens.Spacing.toastBadgeSize, height: DesignTokens.Spacing.toastBadgeSize)
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }

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
                .stroke(item.kind.color.opacity(0.30), lineWidth: 0.5)
        )
        .shadow(color: DesignTokens.Shadow.toastShadow, radius: DesignTokens.Shadow.toastRadius, y: DesignTokens.Shadow.toastOffsetY)
    }
}
