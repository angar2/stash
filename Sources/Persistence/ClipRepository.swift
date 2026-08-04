// 클립 CRUD 8메서드를 정의하는 Persistence Layer protocol (API-SPEC §3-1 정합)
import Foundation

/// stash 클립 영속화 인터페이스.
/// 구현체: `GRDBClipRepository` (v1.0) / `InMemoryClipRepository` (테스트 mock).
protocol ClipRepository: Sendable {

    /// 최신순 정렬 클립 목록 fetch (popover 호출 시).
    /// - Returns: `is_pinned DESC, last_used_at DESC` 정렬, 최대 `보관 한도 + 10` row (한도는 사용자 설정 — TASK-100).
    func fetchAll() async throws -> [Clip]

    /// 핀 제외 클립 개수 (TASK-100). 보관 한도를 어디까지 내릴 수 있는지 정하는 비교 기준이다 —
    /// 한도는 핀이 아닌 클립에만 적용되므로 목록 전체 개수를 쓰면 핀 개수만큼 잘못 부풀려진다.
    func unpinnedCount() async throws -> Int

    /// 새 클립 insert + 보관 한도 자동 정리 (LRU). DB 작업은 한 트랜잭션 atomic.
    /// - Note: LRU 정리로 삭제된 클립의 디스크 파일 삭제는 호출자 책임.
    /// - Returns: LRU 정리로 삭제된 클립 목록.
    @discardableResult
    func insert(_ clip: Clip) async throws -> [Clip]

    /// LIKE 검색 (case-insensitive, substring 매칭).
    ///
    /// 검색 대상 (TASK-103, DATA-MODEL §7) — 본문(`body`) + 파일 클립의 원본 경로(`file_original_path`)
    /// + 묶음 클립 항목의 원본 경로(`file_paths_json`). 전체 경로가 대상이라 파일명뿐 아니라
    /// 상위 폴더명으로도 찾을 수 있다. **내부 보관 복사본 경로(`file_path`)는 제외** — 이름이
    /// `UUID_원본파일명` 형태라 짧은 검색어와 우연히 매칭되는 잡음이 된다.
    ///
    /// 검색어의 `%` / `_` / `!` 는 와일드카드가 아니라 *글자 그대로* 매칭된다 (TASK-103).
    ///
    /// 검색되지 않는 것 — 원본 경로가 없는 이미지 클립(화면 캡처 등). 본문도 경로도 없어 대조할 문자열이 없다.
    /// - Parameter query: 빈 문자열이면 `fetchAll()` 동일 동작.
    func search(query: String) async throws -> [Clip]

    /// paste 합성 성공 후 호출 — `last_used_at` 갱신 (정렬 최상단 이동).
    func updateLastUsedAt(id: UUID) async throws

    /// Pin 토글. 한도 10 초과 시 `DatabaseError.pinLimitReached` throw.
    /// TASK-098 검수 정정 — 핀을 켜면 **가장 낮은 빈 자리**(`pin_slot` 1~10)를 배정하고,
    /// 해제하면 **그 자리만 비운다**(다른 핀의 자리·번호·조합 불변) + 명칭(`pin_alias`) 초기화.
    func togglePin(id: UUID) async throws

    /// 지정한 *자리* (1~10)에 핀을 꽂는다 (TASK-098 검수 정정). 설정 `PIN 단축키` 빈 행에서 새 핀을 만드는 경로 전용.
    /// `togglePin` 은 가장 낮은 빈 자리를 배정하므로 *사용자가 클릭한 번호* 를 지킬 수 없다.
    /// - Returns: 꽂았으면 `true`. 대상 없음 / 자리 점유 / 범위 밖이면 `false`.
    @discardableResult
    func pinAtSlot(id: UUID, slot: Int) async throws -> Bool

    /// 핀 표시용 명칭 저장 (TASK-098). `nil` 이면 해제(컬럼 NULL).
    /// 호출 전 `PinPasteShortcutResolver.normalizeAlias` 로 공백 제거·상한(40자) 적용을 마친 값을 넘긴다.
    /// 표시 전용 컬럼이라 `last_used_at` 등 다른 컬럼은 건드리지 않는다.
    func setPinAlias(id: UUID, alias: String?) async throws

    /// 클립 본문 수정 (TASK-098). **텍스트 타입만** 허용하며 빈 문자·공백만은 거부한다.
    /// 수정은 *사용 이력이 아니므로* `last_used_at` 을 갱신하지 않는다 (히스토리 최근사용순 정렬 불변).
    /// - Returns: 실제로 반영됐으면 `true`. 대상 없음 / 텍스트 아님 / 빈 값이면 `false`.
    @discardableResult
    func updateBody(id: UUID, body: String) async throws -> Bool

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
