// NSStatusItem 등록 + 좌클릭 Method1Window (NSPanel, Liquid Glass) / 우클릭 NSMenu + 권한 상태 추종 아이콘 페어
// 메뉴바 아이콘 = SwiftUI Canvas (TrayIconView variant 2) → ImageRenderer → NSImage Template
import AppKit
import SwiftUI
import Combine
import OSLog

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let method1Window: Method1Window
    private let menu: NSMenu
    private var permissionCancellable: AnyCancellable?

    init(
        permissionStatusPublisher: AnyPublisher<PermissionStatus, Never>,
        clipsViewModel: ClipsViewModel,
        onOpenSettings: @MainActor @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.method1Window = Method1Window(
            viewModel: clipsViewModel,
            onOpenSettings: onOpenSettings
        )

        let m = NSMenu()
        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        m.addItem(quitItem)
        self.menu = m

        configureButton()
        applyPermissionAppearance(.unknown)

        permissionCancellable = permissionStatusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.applyPermissionAppearance(status)
            }

        Logger.appLifecycle.info("StatusItemController initialized — NSStatusItem registered")
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeMenuBarImage(active: false)
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// SwiftUI Canvas (TrayIconView variant 2) → NSImage Template 변환 (icons.jsx 100% 정합)
    private static func makeMenuBarImage(active: Bool) -> NSImage? {
        let size: CGFloat = 18
        let renderer = ImageRenderer(
            content: TrayIconView(full: active, size: size)
                .foregroundStyle(Color.black)
                .frame(width: size, height: size)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let nsImage = renderer.nsImage else { return nil }
        nsImage.isTemplate = true
        nsImage.size = NSSize(width: size, height: size)
        return nsImage
    }

    private func applyPermissionAppearance(_ status: PermissionStatus) {
        guard let button = statusItem.button else { return }
        let active = (status == .granted)
        button.image = Self.makeMenuBarImage(active: active)
        button.image?.isTemplate = true
        Logger.appLifecycle.info("StatusItem icon updated for permission status: \(String(describing: status))")
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseUp:
            showMenu()
        case .leftMouseUp:
            togglePopover()
        default:
            break
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if method1Window.isVisible {
            method1Window.hide()
        } else {
            method1Window.show(below: button)
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
