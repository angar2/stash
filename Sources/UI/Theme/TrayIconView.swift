// 적층 카드 아이콘 — icons.jsx TrayIconVariant2 SVG path 100% 정합
// viewBox 0 0 22 22 — 3 layer rect (top opacity 0.5/0.4 / mid 0.75/0.5 / bottom fill or stroke only)
import SwiftUI

struct TrayIconView: View {
    let full: Bool
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 22.0
            let topOpacity: CGFloat = full ? 0.5 : 0.4
            let midOpacity: CGFloat = full ? 0.75 : 0.5
            let lineWidth: CGFloat = 1.4

            // 상단 카드 (x=4 y=5 w=14 h=3.5 rx=1.2 stroke opacity ↑)
            let topRect = CGRect(x: 4 * scale, y: 5 * scale, width: 14 * scale, height: 3.5 * scale)
            context.opacity = topOpacity
            context.stroke(
                Path(roundedRect: topRect, cornerRadius: 1.2 * scale),
                with: .foreground,
                lineWidth: lineWidth
            )

            // 중간 카드 (x=3 y=9 w=16 h=4 rx=1.2 stroke opacity ↑)
            let midRect = CGRect(x: 3 * scale, y: 9 * scale, width: 16 * scale, height: 4 * scale)
            context.opacity = midOpacity
            context.stroke(
                Path(roundedRect: midRect, cornerRadius: 1.2 * scale),
                with: .foreground,
                lineWidth: lineWidth
            )

            // 하단 카드 (x=2 y=13.5 w=18 h=4.5 rx=1.4 — full=true: fill+stroke / full=false: stroke only)
            let bottomRect = CGRect(x: 2 * scale, y: 13.5 * scale, width: 18 * scale, height: 4.5 * scale)
            let bottomPath = Path(roundedRect: bottomRect, cornerRadius: 1.4 * scale)
            context.opacity = 1.0
            if full {
                context.fill(bottomPath, with: .foreground)
            }
            context.stroke(bottomPath, with: .foreground, lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
    }
}
