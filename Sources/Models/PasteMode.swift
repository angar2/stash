// 붙여넣기 모드 enum — UserDefaults @AppStorage 직렬화 (API-SPEC §2-2 정합)
import Foundation

enum PasteMode: String, Codable, Sendable {
    case autoPaste
    case copyBack
}
