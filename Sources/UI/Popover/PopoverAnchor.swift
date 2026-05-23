// popover 진입 anchor 5종 — 환경설정 디스플레이 탭 *보관함 오픈 위치* (TASK-054)
import Foundation
import AppKit

/// 방식 2 popover 진입 anchor — UX-UI §4-3 / API-SPEC §2-2 단일 진실.
/// UserDefaults 직렬화 (`String` Codable). 사용자 선택 5종 — default `.topRight` (TASK-065).
/// case 순서 = Picker 노출 순서 (UX-UI §4-3 *기본 오픈 위치* sub-row 1) — `우상단 → 우하단 → 좌상단 → 좌하단 → 중앙`.
enum PopoverAnchor: String, Codable, Sendable, CaseIterable {
    case topRight
    case bottomRight
    case topLeft
    case bottomLeft
    case center

    static let `default`: PopoverAnchor = .topRight

    /// visibleFrame 기준 panel origin 계산 (NSPanel bottom-up 좌표계).
    /// inset = 화면 가장자리 여유 (default 0 — `Constants.popoverInsetBottom` 정합).
    /// 순수 함수 — 단위 테스트 진입점 (NSPanel 없이 입출력만 검증).
    func origin(panelSize: NSSize, visibleFrame: NSRect, inset: CGFloat = 0) -> NSPoint {
        switch self {
        case .topRight:
            return NSPoint(
                x: visibleFrame.maxX - panelSize.width - inset,
                y: visibleFrame.maxY - panelSize.height - inset
            )
        case .bottomRight:
            return NSPoint(
                x: visibleFrame.maxX - panelSize.width - inset,
                y: visibleFrame.minY + inset
            )
        case .topLeft:
            return NSPoint(
                x: visibleFrame.minX + inset,
                y: visibleFrame.maxY - panelSize.height - inset
            )
        case .bottomLeft:
            return NSPoint(
                x: visibleFrame.minX + inset,
                y: visibleFrame.minY + inset
            )
        case .center:
            return NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.midY - panelSize.height / 2
            )
        }
    }

    /// Localizable.xcstrings 키 lookup 보조. 사용자 표시용 라벨은 `popoverAnchor.<rawValue>` 키 lookup.
    var localizationKey: String {
        "popoverAnchor.\(rawValue)"
    }
}
