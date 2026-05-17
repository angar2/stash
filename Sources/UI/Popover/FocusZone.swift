// popover focus zone 상태 머신 — 방향키/숫자키 내비 + 행 단위 hover 하이라이트 (UX-UI §5-1 정합)
// TASK-025 — `.search` case 폐기. 검색바 always-active 정책으로 검색 활성 단계 개념 자체 제거.
import Foundation

enum FocusZone: String, Equatable, Sendable {
    case clip
    case pin
    case settings
}
