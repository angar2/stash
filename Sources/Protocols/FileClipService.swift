// 파일 클립 저장·조회·삭제 추상화 protocol — Sandbox 마이그레이션 대비
import Foundation

protocol FileClipService: Sendable {
    /// 클립보드 직접 데이터 (스크린샷 등) 카피 — `clips/{uuid}.ext` 생성.
    func saveData(_ data: Data, type: ClipType) async throws -> StoredFile
    /// Finder 원본 파일 카피 — 100MB 초과 시 경로 참조 fallback (`isFileExternal = true`).
    func saveFile(at sourceURL: URL) async throws -> StoredFile
    /// 디스크 파일 삭제 (DB row 삭제 후 호출). `isFileExternal = true` 클립은 삭제 X.
    func delete(_ clip: Clip) async throws
}
