// 클립 행 이미지 썸네일 캐시 + CGImageSource 다운스케일 (TASK-082 Phase 2 — M1/M4/M5 해소)
import AppKit
import ImageIO
import OSLog

/// 메인 클립 리스트 행 / 핀 사이드바 행 / 검색 결과 행 등 *썸네일 표시 영역* 의 NSImage 풀해상도 로드 차단.
///
/// 기존 패턴 (TASK-082 Phase 1 베이스라인): `NSImage(contentsOfFile:)` 호출 후 SwiftUI `Image(nsImage:)` 가
/// render 시점에 풀해상도 backing store 잡음. 200 행 × 평균 8MB = 약 1.5GB peak (비교 앱 3GB 케이스의 핵심 원인).
///
/// 본 캐시는 `CGImageSourceCreateThumbnailAtIndex` 로 *target pixel size* 까지 다운스케일 + `NSCache` LRU 관리.
/// 캐시 hit 시 동일 `NSImage` instance 반환 — SwiftUI body 재평가마다 재로드 차단.
///
/// PinSidebarView 가 `ClipRowView` 재사용이라 본체 + 사이드바 양쪽 동일 캐시 활용 (M4 자연 해소).
/// `PopoverPanel.mount()` 가 매 popover open 시 `NSHostingView` rebuild 해도 캐시 hit 라 재로드 X (M5 자연 해소).
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage>

    /// totalCostLimit = 50MB. 다운스케일 후 썸네일 1개 약 12KB (72px × 72px × 4 RGBA) — 50MB 면 200 썸네일 × 약 12KB ≈ 2.4MB 충분 커버 + LRU 안전 margin.
    /// 사용자 환경 (Retina 2x — 36pt × 32pt 썸네일 = 72px × 64px 약 18KB) 정합. 후속 task 에서 사용자 풀 확장 시 조정 가능.
    private static let totalCostLimitBytes: Int = 50 * 1024 * 1024

    private init() {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = Self.totalCostLimitBytes
        self.cache = cache
    }

    // MARK: - Public API

    /// 캐시 hit/miss 분기 + 다운스케일 로드. 잘못된 path / 디코드 실패 → nil (`NSImage(contentsOfFile:)` 호출 시그니처 동일).
    ///
    /// - Parameters:
    ///   - filePath: 디스크 절대 경로. `clip.filePath` 가 진실 소스.
    ///   - targetSize: SwiftUI frame 단위 (pt). Retina backing scale 자동 곱셈 — render pixel size 자동 계산.
    /// - Returns: 다운스케일된 `NSImage` (size = targetSize 명시) 또는 nil.
    func thumbnail(for filePath: String, targetSize: NSSize) -> NSImage? {
        let key = filePath as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let url = URL(fileURLWithPath: filePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Logger.ui.debug("ThumbnailCache: CGImageSource create failed — \(filePath, privacy: .public)")
            return nil
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let maxPixel = max(targetSize.width, targetSize.height) * scale
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,  // EXIF orientation 정합
            kCGImageSourceShouldCache: false                    // CGImageSource 자체 캐시 X — NSCache 단일 진실
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            Logger.ui.debug("ThumbnailCache: thumbnail create failed — \(filePath, privacy: .public)")
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: targetSize)
        let cost = cgImage.width * cgImage.height * 4  // RGBA 8-bit 가정
        cache.setObject(nsImage, forKey: key, cost: cost)
        return nsImage
    }

    /// 명시 evict — 클립 삭제 site 후속 task 가 호출 (Phase 3 이후 정합).
    func evict(filePath: String) {
        cache.removeObject(forKey: filePath as NSString)
    }

    /// 전체 evict — 테스트 격리 또는 메모리 압박 대응.
    func evictAll() {
        cache.removeAllObjects()
    }

    // MARK: - Test entry points (internal)

    /// 단위 테스트 진입점 — 캐시 hit/miss 검증.
    func cachedObject(for filePath: String) -> NSImage? {
        cache.object(forKey: filePath as NSString)
    }

    /// 단위 테스트 진입점 — totalCostLimit 설정값 검증.
    var totalCostLimit: Int {
        cache.totalCostLimit
    }
}
