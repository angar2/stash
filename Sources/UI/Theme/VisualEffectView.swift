// SwiftUI body 위 디자인 컬러 오버레이만 박음 (Liquid Glass blur 자체는 panel.contentView = NSVisualEffectView로 처리)
// popover.jsx L280-292 정합 — base blur(NSVisualEffectView) + tint overlay (rgba 0.72 light / 0.62 dark)
import SwiftUI
import AppKit

extension View {
    /// popover/sidebar 컬러 오버레이 (NSVisualEffectView가 panel.contentView 레벨에서 base blur 담당)
    func liquidGlassBackground(
        cornerRadius: CGFloat,
        overlayColor: Color = DesignTokens.Colors.popoverBackground
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(overlayColor)
        )
    }
}

// SwiftUI에서 직접 NSVisualEffectView 사용 (Settings/Onboarding/Toast의 in-body Material — popover/panel과 별개로 SwiftUI body 내부에서 vibrancy)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active
    var emphasized: Bool = false

    init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        emphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.emphasized = emphasized
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = emphasized
    }
}
