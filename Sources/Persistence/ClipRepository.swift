// 클립 CRUD 8메서드를 정의하는 Persistence Layer protocol (API-SPEC §3-1 정합)
import Foundation

/// stash 클립 영속화 인터페이스.
/// 구현체: `GRDBClipRepository` (v1.0) / `InMemoryClipRepository` (테스트 mock).
protocol ClipRepository: Sendable {

    /// 최신순 정렬 클립 목록 fetch (popover 호출 시).
    /// - Returns: `is_pinned DESC, last_used_at DESC` 정렬, 최대 210 row.
    func fetchAll() async throws -> [Clip]

    /// 새 클립 insert + 200 한도 자동 정리 (LRU). DB 작업은 한 트랜잭션 atomic.
    /// - Note: LRU 정리로 삭제된 클립의 디스크 파일 삭제는 호출자 책임.
    /// - Returns: LRU 정리로 삭제된 클립 목록.
    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip]

    /// LIKE 검색 (body 컬럼만, case-insensitive, substring 매칭).
    /// - Parameter query: 빈 문자열이면 `fetchAll()` 동일 동작.
    func search(query: String) async throws -> [Clip]

    /// paste 합성 성공 후 호출 — `last_used_at` 갱신 (정렬 최상단 이동).
    func updateLastUsedAt(id: UUID) async throws

    /// Pin 토글. 한도 10 초과 시 `DatabaseError.pinLimitReached` throw.
    func togglePin(id: UUID) async throws

    /// 개별 클립 DB row 삭제. 디스크 파일 삭제는 호출자 책임.
    /// - Returns: 삭제된 클립 (해당 id 없으면 nil).
    @discardableResult
    func delete(id: UUID) async throws -> Clip?

    /// pinned 제외 전체 DB row 삭제. 디스크 파일 삭제는 호출자 책임.
    /// - Returns: 삭제된 클립 목록.
    @discardableResult
    func deleteAllExceptPinned() async throws -> [Clip]

    /// DB 손상 자동 복구 — 백업 + 새 빈 DB 생성. throws X (최후 fallback).
    func recoverFromCorruption() async
}
