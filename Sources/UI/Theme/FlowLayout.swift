// CSS flex-wrap: wrap 정합 SwiftUI Layout — 가로 부족 시 다음 줄로 wrap
// popover.jsx L186 *display: flex, flexWrap: wrap, gap: 10* 정합
import SwiftUI

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 4) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let (size, _) = layout(subviews: subviews, in: maxWidth)
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, positions) = layout(subviews: subviews, in: bounds.width)
        for (idx, sub) in subviews.enumerated() {
            let pos = positions[idx]
            let subSize = sub.sizeThatFits(.unspecified)
            sub.place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: ProposedViewSize(subSize)
            )
        }
    }

    private func layout(subviews: Subviews, in maxWidth: CGFloat) -> (CGSize, [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                // wrap
                maxRowWidth = max(maxRowWidth, currentX - horizontalSpacing)
                currentX = 0
                currentY += rowMaxHeight + verticalSpacing
                rowMaxHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + horizontalSpacing
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, currentX - horizontalSpacing)
        let total = CGSize(width: maxRowWidth, height: currentY + rowMaxHeight)
        return (total, positions)
    }
}
