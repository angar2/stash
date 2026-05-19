// 파일 클립 저장·조회·삭제 추상화 protocol — Sandbox 마이그레이션 대비
import Foundation

protocol FileClipService: Sendable {
    /// 클립보드 직접 데이터 (스크린샷 등) 카피 — `clips/{uuid}.ext` 생성.
    func saveData(_ data: Data, type: ClipType) async throws -> StoredFile
    /// Finder 원본 파일 카피 — 100MB 초과 시 경로 참조 fallback (`isFileExternal = true`).
    func saveFile(at sourceURL: URL) async throws -> StoredFile
    /// TASK-026 — 다중 파일 카피. 어느 하나라도 실패 시 *전체 throw* + 이미 카피된 N-K개 cleanup (옵션 A).
    /// - Returns: 성공 시 N개 `StoredFile` 배열 (입력 순서 보존).
    func saveFiles(at sources: [URL]) async throws -> [StoredFile]
    /// 디스크 파일 삭제 (DB row 삭제 후 호출). `isFileExternal = true` 클립은 삭제 X.
    /// TASK-026 — `clip.isMultiFile` 인 경우 entries 순회 cleanup (entry별 `isFileExternal=false` 만 삭제).
    func delete(_ clip: Clip) async throws
    /// TASK-034 — clips/ 폴더 안 파일 중 `referencedPaths` (절대경로 set) 에 미포함된 고아 파일 삭제.
    /// 앱 시작 시 자동 회수 + 전체 삭제 시 일괄 정리 두 호출처가 공유. silent + OSLog (DATA-MODEL §6 정합).
    func sweepOrphans(referencedPaths: Set<String>) async
}
