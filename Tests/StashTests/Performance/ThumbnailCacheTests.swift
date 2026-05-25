// ThumbnailCache 단위 테스트 (TASK-082 Phase 2)
import Testing
import Foundation
import AppKit
@testable import stash

@MainActor
@Suite("ThumbnailCache — TASK-082 Phase 2", .serialized)
struct ThumbnailCacheTests {

    // MARK: - Fixtures

    /// 임시 폴더 안 단색 PNG 1건 생성. width × height pt 박은 후 PNG 인코딩.
    private func createTestImage(width: CGFloat, height: CGFloat) -> (folder: URL, path: String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stash-thumbnailtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let path = folder.appendingPathComponent("img.png").path
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: path))
        }
        return (folder, path)
    }

    private func cleanup(folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    private func resetCache() {
        ThumbnailCache.shared.evictAll()
    }

    // MARK: - Tests

    @Test("잘못된 path → nil")
    func invalidPath() {
        resetCache()
        let result = ThumbnailCache.shared.thumbnail(
            for: "/nonexistent/path-\(UUID().uuidString).png",
            targetSize: NSSize(width: 36, height: 32)
        )
        #expect(result == nil)
    }

    @Test("정상 path 첫 호출 → NSImage 반환 + 캐시 저장")
    func firstCall_loadsAndCaches() {
        resetCache()
        let (folder, path) = createTestImage(width: 1920, height: 1080)
        defer { cleanup(folder: folder) }

        let target = NSSize(width: 36, height: 32)
        let result = ThumbnailCache.shared.thumbnail(for: path, targetSize: target)
        #expect(result != nil)
        // 캐시 안에 박혔는지 확인
        #expect(ThumbnailCache.shared.cachedObject(for: path) != nil)
    }

    @Test("동일 path 두 번째 호출 → 캐시 hit (동일 instance)")
    func secondCall_returnsCachedInstance() {
        resetCache()
        let (folder, path) = createTestImage(width: 1920, height: 1080)
        defer { cleanup(folder: folder) }

        let target = NSSize(width: 36, height: 32)
        let first = ThumbnailCache.shared.thumbnail(for: path, targetSize: target)
        let second = ThumbnailCache.shared.thumbnail(for: path, targetSize: target)
        #expect(first != nil)
        #expect(second != nil)
        #expect(first === second)
    }

    @Test("targetSize 적용 — pixel size ≤ maxPixel × backingScale")
    func targetSize_downscaled() {
        resetCache()
        let (folder, path) = createTestImage(width: 1920, height: 1080)
        defer { cleanup(folder: folder) }

        let target = NSSize(width: 36, height: 32)
        guard let result = ThumbnailCache.shared.thumbnail(for: path, targetSize: target) else {
            Issue.record("thumbnail returned nil")
            return
        }
        // representations 안 NSBitmapImageRep 또는 CGImageRep 가 실제 pixel size 보유.
        // maxPixel = max(36, 32) × backingScale (2.0 가정 — Retina) = 72px.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let maxPx = Int(max(target.width, target.height) * scale)
        guard let rep = result.representations.first else {
            Issue.record("no representations")
            return
        }
        // CGImage 기반 representation 은 pixelsWide / pixelsHigh 가 actual pixel.
        let pixelsWide = rep.pixelsWide
        let pixelsHigh = rep.pixelsHigh
        // CGImageSource thumbnail 은 *비율 유지* 라 둘 중 하나가 maxPixel 도달, 다른 하나는 비율 만큼 작아짐.
        #expect(pixelsWide <= maxPx)
        #expect(pixelsHigh <= maxPx)
        #expect(max(pixelsWide, pixelsHigh) == maxPx || max(pixelsWide, pixelsHigh) == maxPx - 1)
    }

    @Test("evict(filePath:) → 다음 호출 시 새 instance")
    func evict_invalidatesCache() {
        resetCache()
        let (folder, path) = createTestImage(width: 800, height: 600)
        defer { cleanup(folder: folder) }

        let target = NSSize(width: 36, height: 32)
        let first = ThumbnailCache.shared.thumbnail(for: path, targetSize: target)
        ThumbnailCache.shared.evict(filePath: path)
        #expect(ThumbnailCache.shared.cachedObject(for: path) == nil)
        let second = ThumbnailCache.shared.thumbnail(for: path, targetSize: target)
        #expect(second != nil)
        #expect(first !== second)
    }

    @Test("totalCostLimit == 50MB")
    func totalCostLimit() {
        #expect(ThumbnailCache.shared.totalCostLimit == 50 * 1024 * 1024)
    }

    @Test("evictAll() → 모든 키 cache miss")
    func evictAll_clearsAll() {
        resetCache()
        let (folder1, path1) = createTestImage(width: 800, height: 600)
        let (folder2, path2) = createTestImage(width: 800, height: 600)
        defer {
            cleanup(folder: folder1)
            cleanup(folder: folder2)
        }
        let target = NSSize(width: 36, height: 32)
        _ = ThumbnailCache.shared.thumbnail(for: path1, targetSize: target)
        _ = ThumbnailCache.shared.thumbnail(for: path2, targetSize: target)
        #expect(ThumbnailCache.shared.cachedObject(for: path1) != nil)
        #expect(ThumbnailCache.shared.cachedObject(for: path2) != nil)

        ThumbnailCache.shared.evictAll()
        #expect(ThumbnailCache.shared.cachedObject(for: path1) == nil)
        #expect(ThumbnailCache.shared.cachedObject(for: path2) == nil)
    }
}
