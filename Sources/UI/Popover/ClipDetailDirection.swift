// 클립 상세 sub-window + 핀 사이드바의 좌/우 방향 결정 단일 진실 헬퍼 (TASK-055)
import Foundation
import CoreGraphics

/// 클립 상세 sub-window / 핀 사이드바 진입 방향. 좌측 default + 좌측 가장자리 막힘 시 우측 fallback.
/// 두 영역이 *동일 결정 헬퍼 호출* 로 일관성 보장 — `ClipDetailDirection.resolve` 가 anchorFrame 기반 단일 분기.
public enum ClipDetailDirection: String, Sendable, Equatable, CaseIterable {
    case left
    case right

    /// anchorFrame 기준으로 sub-panel (또는 사이드바) 의 진입 방향 결정.
    /// 순수 함수 — 단위 테스트 진입점.
    ///
    /// - Parameters:
    ///   - anchorFrame: 기준 윈도우 frame (본체 popover 또는 PinSidebar, screen 좌표계 bottom-up).
    ///   - totalWidth: sub-panel (또는 사이드바) 의 총 폭. detail 의 경우 본문 + 꼭지 합산.
    ///   - gap: anchorFrame 과 sub-panel 사이 간격.
    ///   - safe: 화면 가장자리 safe margin.
    ///   - visibleFrame: 현재 화면의 visibleFrame (메뉴바 + Dock 제외).
    ///
    /// - Returns: 좌측 통과 → `.left` / 좌측 막힘 + 우측 통과 → `.right` / 양쪽 막힘 → `.left` 강제 (화면 밖 픽셀 일부 허용).
    public static func resolve(
        anchorFrame: CGRect,
        totalWidth: CGFloat,
        gap: CGFloat,
        safe: CGFloat,
        visibleFrame: CGRect
    ) -> ClipDetailDirection {
        // 좌측 진입 시 originX = anchorFrame.minX - gap - totalWidth. 통과 조건 = originX >= visibleFrame.minX + safe.
        let leftOriginX = anchorFrame.minX - gap - totalWidth
        let leftPasses = leftOriginX >= visibleFrame.minX + safe
        if leftPasses {
            return .left
        }
        // 우측 진입 시 originX = anchorFrame.maxX + gap. 통과 조건 = originX + totalWidth <= visibleFrame.maxX - safe.
        let rightEndX = anchorFrame.maxX + gap + totalWidth
        let rightPasses = rightEndX <= visibleFrame.maxX - safe
        if rightPasses {
            return .right
        }
        // 양쪽 막힘 — .left 강제 (사용자 결정. 화면 밖 픽셀 일부 허용 정책. 호출자가 setFrame 클램프 추가 가능).
        return .left
    }

    /// 결정된 방향 + anchorFrame 기준으로 sub-panel originX 산출.
    /// 호출자가 `panel.setFrame` 박을 때 사용. 화면 가장자리 클램프는 호출자 책임 (양쪽 막힘 케이스 등).
    public func originX(anchorFrame: CGRect, totalWidth: CGFloat, gap: CGFloat) -> CGFloat {
        switch self {
        case .left:
            return anchorFrame.minX - gap - totalWidth
        case .right:
            return anchorFrame.maxX + gap
        }
    }
}
