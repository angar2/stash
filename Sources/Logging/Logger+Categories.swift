// OSLog Logger 카테고리 분리 — 영역별 로그 구분
import OSLog

extension Logger {
    static let clipboard = Logger(subsystem: "com.angar2.stash", category: "clipboard")
    static let database  = Logger(subsystem: "com.angar2.stash", category: "database")
    static let hotkey    = Logger(subsystem: "com.angar2.stash", category: "hotkey")
    static let paste     = Logger(subsystem: "com.angar2.stash", category: "paste")
    static let permission = Logger(subsystem: "com.angar2.stash", category: "permission")
    static let ui        = Logger(subsystem: "com.angar2.stash", category: "ui")
}
