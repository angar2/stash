// macOS frontmost (가장 위에 있는) 사용자 활성 앱 번들 ID 노출 protocol — NSWorkspace 추상화로 테스트 가능성 확보
import Foundation

protocol FrontmostAppTracking: Sendable {
    /// 마지막으로 활성화된 *비-stash* 앱 번들 ID. stash 자체 활성화는 갱신 skip.
    /// nil = 추적 정보 없음 (앱 시작 직후 또는 시스템 상태 미확정).
    @MainActor var currentBundleId: String? { get }
}
