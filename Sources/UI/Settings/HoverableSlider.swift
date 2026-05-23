// NSSlider wrap — knob 영역에만 hover 시각 효과 (TASK-065)
// SwiftUI Slider 는 knob 단독 hover detection 불가 (.onHover 가 트랙 전체 영역 발화) → NSViewRepresentable 로 NSSlider 직접 wrap + NSTrackingArea mouseMoved 로 knob 영역 추적.
import SwiftUI
import AppKit

@MainActor
struct HoverableSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// trackFillColor — `DesignTokens.Colors.accent` (AccentColorMode 분기 추종) 정합. updateNSView 에서 매번 갱신.
    let tint: Color

    func makeNSView(context: Context) -> _HoverableSliderView {
        let cell = _HoverableSliderCell()
        let view = _HoverableSliderView()
        view.cell = cell
        view.minValue = range.lowerBound
        view.maxValue = range.upperBound
        view.doubleValue = value
        view.isContinuous = true
        view.target = context.coordinator
        view.action = #selector(Coordinator.valueChanged(_:))
        view.trackFillColor = NSColor(tint)
        return view
    }

    func updateNSView(_ nsView: _HoverableSliderView, context: Context) {
        if abs(nsView.doubleValue - value) > 0.0001 {
            nsView.doubleValue = value
        }
        nsView.trackFillColor = NSColor(tint)
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HoverableSlider
        init(parent: HoverableSlider) { self.parent = parent }
        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

/// knob 영역 hover 시 옅은 ring overlay 그리기.
@MainActor
final class _HoverableSliderCell: NSSliderCell {
    var isKnobHovered: Bool = false {
        didSet { controlView?.needsDisplay = true }
    }

    override func drawKnob(_ knobRect: NSRect) {
        super.drawKnob(knobRect)
        guard isKnobHovered else { return }
        let ringRect = knobRect.insetBy(dx: -3, dy: -3)
        let path = NSBezierPath(ovalIn: ringRect)
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

/// NSTrackingArea 로 mouseMoved 추적 + cell.knobRect 와 비교해 knob hover 분기.
@MainActor
final class _HoverableSliderView: NSSlider {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard let cell = self.cell as? _HoverableSliderCell else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let knobRect = cell.knobRect(flipped: isFlipped)
        cell.isKnobHovered = knobRect.contains(pt)
    }

    override func mouseExited(with event: NSEvent) {
        (self.cell as? _HoverableSliderCell)?.isKnobHovered = false
    }
}
