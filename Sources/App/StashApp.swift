// @main 진입점 + Composition Root 골격 — 실제 와이어링은 Stage 2~3에서 완성
import SwiftUI

@main
struct StashApp: App {
    init() {
        // Stage 2~3에서 의존성 주입 + 와이어링 완성
        // (ClipboardWatcher / HotkeyManager / PasteService / Repository 등)
    }

    var body: some Scene {
        // NOTE: MenuBarExtra 미사용 — NSStatusItem 직접 사용 (ARCHITECTURE §9-2)
        // StatusItemController 인스턴스화는 Stage 3 Composition Root 완성 시점 이동
        Settings {
            EmptyView()
        }
    }
}
