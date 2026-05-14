// popover focus zone 상태 머신 — 방향키/숫자키 내비 + 검색 IME 분기 (UX-UI §5-1 정합)
import Foundation

enum FocusZone: String, Equatable, Sendable {
    case search
    case clip
    case pin
    case settings
}
