// 클립보드 처리 에러 도메인 (API-SPEC §5 정합)
import AppKit

enum ClipboardError: Error, Sendable {
    case pasteboardUnavailable
    case typeNotSupported(NSPasteboard.PasteboardType)
    case fileTooLarge(size: Int)
    case ignoredByPolicy(reason: String)
}

extension ClipboardError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .pasteboardUnavailable:
            return String(localized: "error.clipboard.pasteboard_unavailable")
        case .typeNotSupported:
            return String(localized: "error.clipboard.type_not_supported")
        case .fileTooLarge:
            return String(localized: "error.clipboard.file_too_large")
        case .ignoredByPolicy:
            return String(localized: "error.clipboard.ignored_by_policy")
        }
    }
}
