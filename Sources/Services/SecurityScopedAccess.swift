// 파일 클립 원본의 security-scoped 북마크 생성과 접근 열기·닫기 (TASK-113 — App Store판 샌드박스 대응)
import Foundation
import OSLog

/// 북마크로 원본 접근을 실제로 여닫는 창구. 프로덕션은 `BookmarkResourceOpener`, 단위 테스트는 가짜를 주입한다.
protocol ScopedResourceOpening: Sendable {
    /// 북마크로 접근을 시작한다. 시작했으면 닫을 때 넘길 URL, 시작하지 못했으면 nil.
    func open(_ bookmark: Data) -> URL?
    func close(_ url: URL)
}

/// 샌드박스 앱은 클립보드로 받은 파일 접근권을 그 프로세스 동안만 가진다. 재실행 뒤에도 썸네일·미리보기·
/// 다시 붙여넣기가 원본을 열 수 있도록, 복사 시점에 북마크를 만들어 DB 에 두고(`Clip.fileBookmark` ·
/// `ClipFileEntry.bookmark`) 원본을 읽기 직전에 이 창구로 접근을 되살린다.
///
/// 닫기 정책 — 동시에 열 수 있는 자원 수에 시스템 한도가 있어 오래 열어 두지 않는다.
/// - 읽기(`withAccess`): 쓰고 바로 닫는다.
/// - 붙여넣기(`hold`): 받는 앱이 파일을 읽을 시간이 필요해 *다음 붙여넣기 때* 앞의 것을 닫는다.
///   그래서 늘 열려 있는 것은 마지막 붙여넣기 한 건분뿐이고, 클립 삭제·보관 한도 정리 때 따로 닫을 것이 없다.
///
/// dmg판은 북마크를 만들지 않고(`makeBookmark` 가 nil) 여는 창구도 아무것도 하지 않는다.
final class SecurityScopedAccess: @unchecked Sendable {
    static let shared = SecurityScopedAccess(opener: BookmarkResourceOpener())

    private let opener: any ScopedResourceOpening
    private let lock = NSLock()
    /// 붙여넣기로 열어 둔 자원. 다음 `hold` 때 닫는다.
    private var held: [URL] = []

    init(opener: any ScopedResourceOpening) {
        self.opener = opener
    }

    /// 복사 시점 — 클립보드가 넘겨준 접근권이 살아 있을 때 원본 북마크를 만든다. dmg판·실패 시 nil.
    static func makeBookmark(for url: URL) -> Data? {
        #if APP_STORE
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            Logger.clipboard.error("북마크 생성 실패 — \(url.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// 읽기 — 북마크로 접근을 열고 `body` 를 실행한 뒤 바로 닫는다. nil 북마크는 건너뛴다.
    func withAccess<T>(_ bookmarks: [Data?], _ body: () throws -> T) rethrows -> T {
        let opened = open(bookmarks)
        defer { opened.forEach(opener.close) }
        return try body()
    }

    /// 붙여넣기 — 새 북마크를 연 뒤 앞서 열어 둔 것을 닫는다. 같은 파일이 이어 붙여넣어져도 끊기지 않게 *열고 나서* 닫는다.
    func hold(_ bookmarks: [Data?]) {
        let opened = open(bookmarks)
        lock.lock()
        let previous = held
        held = opened
        lock.unlock()
        previous.forEach(opener.close)
    }

    /// 지금 붙여넣기용으로 열려 있는 자원 수 (단위 테스트 확인용).
    var heldCount: Int {
        lock.lock(); defer { lock.unlock() }
        return held.count
    }

    private func open(_ bookmarks: [Data?]) -> [URL] {
        bookmarks.compactMap { $0 }.compactMap(opener.open)
    }
}

/// 프로덕션 창구 — 북마크를 URL 로 되살려 `startAccessingSecurityScopedResource` 를 부른다.
/// 북마크 해석은 시스템 서비스를 거쳐 비용이 있으므로 해석한 URL 을 북마크별로 기억한다.
final class BookmarkResourceOpener: ScopedResourceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var resolved: [Data: URL] = [:]
    /// 해석 캐시 상한. 넘으면 비운다 — 보관 한도(최대 500) 수준의 클립을 오가도 메모리가 커지지 않게.
    private static let resolvedCacheLimit = 512

    func open(_ bookmark: Data) -> URL? {
        #if APP_STORE
        guard let url = resolve(bookmark) else { return nil }
        guard url.startAccessingSecurityScopedResource() else {
            Logger.clipboard.error("원본 접근 시작 실패 — \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return url
        #else
        return nil
        #endif
    }

    func close(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    private func resolve(_ bookmark: Data) -> URL? {
        lock.lock()
        if let cached = resolved[bookmark] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            // 낡은 북마크(원본 이동·이름 변경)는 되살린 위치가 저장된 경로와 달라 원래 경로를 열 수 없다. 기록만 남긴다.
            if stale {
                Logger.clipboard.info("낡은 북마크 — \(url.lastPathComponent, privacy: .public)")
            }
            lock.lock()
            if resolved.count >= Self.resolvedCacheLimit { resolved.removeAll() }
            resolved[bookmark] = url
            lock.unlock()
            return url
        } catch {
            Logger.clipboard.error("북마크 해석 실패 — error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
