// 다중 파일 묶음 entry 단위 — Clip.filePathsJson 에 배열 JSON 직렬화 (TASK-026, DATA-MODEL §3 케이스 F 정합)
import Foundation

/// 다중 파일 묶음 한 항목 — `originalPath` 우선 paste (단일 파일 케이스 C/D `fileOriginalPath ?? filePath` 정합).
/// JSON 직렬화 시 `JSONEncoder.outputFormatting = [.sortedKeys]` 강제 — dedup 매칭 결정성 보장.
struct ClipFileEntry: Codable, Sendable, Equatable {
    let originalPath: String
    let filePath: String
    let isFileExternal: Bool
    /// 원본 파일의 security-scoped 북마크 (TASK-113). App Store판(샌드박스)만 복사 시점에 만들고, dmg판은 늘 nil 이다.
    /// nil 이면 JSON 에서 키째 빠진다 — dmg판 JSON 은 이 필드가 생기기 전과 같고, 기존 데이터(키 없음)는 nil 로 읽힌다.
    var bookmark: Data? = nil

    enum CodingKeys: String, CodingKey {
        case originalPath = "original_path"
        case filePath = "file_path"
        case isFileExternal = "is_file_external"
        case bookmark
    }
}

extension ClipFileEntry {
    /// JSON 직렬화 — `.sortedKeys` 강제 (dedup 매칭 결정성 보장).
    /// 모든 호출 site (`ClipboardWatcher.buildMultiFileClip` / `ClipFixture.makeMultiFile` / 테스트) 가 본 헬퍼 사용 — 옵션 일관성 + 인라인 중복 제거.
    static func encodeJSON(_ entries: [ClipFileEntry]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entries)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// 중복 판정용 — 북마크를 뺀 항목 (TASK-113). 같은 파일이라도 북마크 바이트는 복사마다 다를 수 있다.
    var withoutBookmark: ClipFileEntry {
        ClipFileEntry(originalPath: originalPath, filePath: filePath, isFileExternal: isFileExternal)
    }

    /// JSON 디코딩 — 실패 시 nil. `Clip.fileEntries` 컴퓨티드 + `PasteService.writeMultiFilePasteboard` / `DirectFileClipService.deleteMultiFileEntries` 사용처 공통화.
    static func decodeJSON(_ json: String) -> [ClipFileEntry]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ClipFileEntry].self, from: data)
    }
}
