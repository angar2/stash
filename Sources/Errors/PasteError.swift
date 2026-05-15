// 붙여넣기 합성 에러 도메인 (API-SPEC §5 정합)
import Foundation

enum PasteError: Error, Sendable {
    case noActiveApplication
    case keyboardSimulationFailed
    case clipboardWriteRollback
    case imageDataLoadFailed   // 이미지 클립의 filePath에서 NSImage 데이터 로드 실패
    case fileURLLoadFailed     // 파일 클립의 fileOriginalPath / filePath 모두 nil
    case unsupportedClipPayload  // 클립 type별 분기에서 필수 데이터 누락 (예: text body=nil)
}

extension PasteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noActiveApplication:
            return String(localized: "error.paste.no_active_application")
        case .keyboardSimulationFailed:
            return String(localized: "error.paste.keyboard_simulation_failed")
        case .clipboardWriteRollback:
            return String(localized: "error.paste.clipboard_write_rollback")
        case .imageDataLoadFailed:
            return String(localized: "error.paste.image_data_load_failed")
        case .fileURLLoadFailed:
            return String(localized: "error.paste.file_url_load_failed")
        case .unsupportedClipPayload:
            return String(localized: "error.paste.unsupported_clip_payload")
        }
    }
}
