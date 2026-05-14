// 데이터베이스 접근 에러 도메인 (API-SPEC §5 정합)
import Foundation

enum DatabaseError: Error, Sendable {
    case migrationFailed(reason: String)
    case corruptionDetected
    case writeBlocked
    case pinLimitReached
}

extension DatabaseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .migrationFailed:
            return String(localized: "error.database.migration_failed")
        case .corruptionDetected:
            return String(localized: "error.database.corruption_detected")
        case .writeBlocked:
            return String(localized: "error.database.write_blocked")
        case .pinLimitReached:
            return String(localized: "error.database.pin_limit_reached")
        }
    }
}
