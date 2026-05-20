// NSStatusItem 등록 + 좌클릭 PopoverWindow(.method1) / 우클릭 NSMenu + 권한 상태 추종 아이콘 페어 + 수집 토글 red dot indicator (TASK-043)
// 메뉴바 아이콘 = SwiftUI Canvas (TrayIconView variant 2) → ImageRenderer → NSImage Template
// TASK-018 — Method1Window 폐기 후 PopoverWindow 단일 인스턴스 (StashApp이 주입) 공유.
// TASK-043 — 수집 비활성 indicator 는 button 위에 NSView dot subview overlay (template image 가 색상을 평탄화하므로 NSView 로 우회).
import AppKit
import SwiftUI
import Combine
import OSLog

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popoverWindow: PopoverWindow
    private let menu: NSMenu
    private var permissionCancellable: AnyCancellable?
    /// TASK-043 — 수집 비활성 시 button 우하단에 표시되는 red dot. captureEnabled=false 시만 button.subview 로 박힘.
    private var captureDotView: NSView?
    private var captureEnabledObserver: NSObjectProtocol?

    init(
        permissionStatusPublisher: AnyPublisher<PermissionStatus, Never>,
        popoverWindow: PopoverWindow
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popoverWindow = popoverWindow

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
        // TASK-043 — UserDefaults 초기값으로 red dot 정합 (앱 시작 시 마지막 상태 복원).
        applyCaptureAppearance(UserDefaults.standard.bool(forKey: Constants.clipboardCaptureEnabledKey, default: true))

        permissionCancellable = permissionStatusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.applyPermissionAppearance(status)
            }

        // TASK-043 — ClipsViewModel.toggleCapture() 가 post 하는 알림 추종.
        captureEnabledObserver = NotificationCenter.default.addObserver(
            forName: Constants.captureEnabledDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = (notification.userInfo?["enabled"] as? Bool) ?? true
            Task { @MainActor [weak self] in
                self?.applyCaptureAppearance(enabled)
            }
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

    /// TASK-043 — 수집 비활성 시 button 우하단에 red dot overlay 표시. systemRed (라이트/다크 자동 추종).
    /// captureEnabled=true 시 dot subview 제거. 첫 호출 (앱 시작) 시점부터 매 토글마다 호출.
    private func applyCaptureAppearance(_ captureEnabled: Bool) {
        guard let button = statusItem.button else { return }
        if captureEnabled {
            captureDotView?.removeFromSuperview()
            captureDotView = nil
            Logger.appLifecycle.info("StatusItem capture indicator: hidden (enabled)")
        } else {
            if captureDotView == nil {
                let dotDiameter: CGFloat = 7
                // 우하단 위치 — button frame 우측 끝에서 dot 만큼 안쪽, 하단에서 살짝 띄움.
                // frame 은 메뉴바 자체 측정 (보통 width ≈ 22~28). 우측에서 dot 만큼 안쪽 + 1pt margin.
                let x = button.bounds.width - dotDiameter - 1
                let y: CGFloat = 1
                let dot = NSView(frame: NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter))
                dot.wantsLayer = true
                dot.layer?.backgroundColor = NSColor.systemRed.cgColor
                dot.layer?.cornerRadius = dotDiameter / 2
                dot.autoresizingMask = [.minXMargin, .maxYMargin]  // 메뉴바 frame 갱신 시 우하단 anchor 유지
                button.addSubview(dot)
                captureDotView = dot
            }
            Logger.appLifecycle.info("StatusItem capture indicator: visible (disabled)")
        }
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
        if popoverWindow.isVisible {
            popoverWindow.hide()
        } else {
            popoverWindow.show(below: button)
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}

// TASK-043 — UserDefaults 미등록 키 default 처리 헬퍼 (true default 보장).
private extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil { return defaultValue }
        return bool(forKey: key)
    }
}
