// FileClipService 반환 타입 — 저장된 파일 정보
import Foundation

struct StoredFile: Sendable {
    let filePath: URL
    let isFileExternal: Bool
}
