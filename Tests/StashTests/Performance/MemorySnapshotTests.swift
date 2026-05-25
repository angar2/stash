// 200건 mix 시나리오 메모리 측정 (TASK-082 Phase 1) — 후속 Phase 회귀 게이트 진실 소스
import Testing
import Foundation
import AppKit
@testable import stash

/// 1920×1080 단색 PNG 50건 강제 디코딩 시나리오. 현재 `ClipRowView.imageThumbnail` 패턴 (NSImage 풀로드 + 캐시 X) 모사.
/// 5회 반복 후 avg-delta 콘솔 출력. assertion = `#expect(true)` — 베이스라인 단계, 임계 assert 후속 Phase 에서 박음.
///
/// 후속 Phase 적용 시 동일 시나리오 재실행 → ThumbnailCache / autoreleasepool / 인덱스 효과 정량 비교.
/// Phase 3 (ThumbnailCache 경유) / Phase 5 (autoreleasepool) / Phase 10 (종합) 끝마다 콘솔 출력 수치 Result 영역 기록.
///
/// **격리 정책**: 본 Suite 가 같은 process 안 1.5GB+ peak 메모리 잡음 → 다른 timing-dependent 테스트 (OnboardingViewModel polling / HoverTooltipController enter delay 등) 영향. 기본 회귀 게이트 (`xcodebuild test`) 에서 제외 + sentinel 파일 `/tmp/stash-memory-tests-enabled` 존재 시만 활성.
/// 명시 측정 명령:
/// ```sh
/// touch /tmp/stash-memory-tests-enabled
/// xcodebuild test -scheme stash -destination 'platform=macOS,arch=arm64' -only-testing:StashTests/MemorySnapshotTests
/// rm /tmp/stash-memory-tests-enabled
/// ```
/// xcodebuild 환경변수 (`-launch-args` / `TEST_RUNNER_*` 등) 가 Swift Testing runner process 에 전달 안 되는 한계 회피.
/// MemorySnapshotTests sentinel — type 외부에 박아 Suite 매크로 circular 회피.
private enum MemoryTestsGate {
    static let sentinelPath = "/tmp/stash-memory-tests-enabled"
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: sentinelPath)
    }
}

@MainActor
@Suite(
    "MemorySnapshot — TASK-082 Phase 1 baseline",
    .serialized,
    .enabled(if: MemoryTestsGate.isEnabled)
)
struct MemorySnapshotTests {

    // MARK: - Fixture

    /// 임시 폴더 안 1920×1080 단색 PNG `count` 건 생성. 단색이라 압축 잘됨 (디스크 약 20KB × N) +
    /// 강제 디코딩 시 backing store RGBA 풀 잡힘 (≈ 8MB × N — Phase 1 베이스라인 50건 ≈ 400MB peak).
    private func createTestImages(count: Int) -> (folder: URL, paths: [String]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stash-memtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let size = NSSize(width: 1920, height: 1080)
        var paths: [String] = []
        paths.reserveCapacity(count)
        for i in 0..<count {
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor(red: CGFloat(i) / CGFloat(max(count, 1)), green: 0.5, blue: 0.8, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            image.unlockFocus()

            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let pngData = rep.representation(using: .png, properties: [:]) {
                let url = folder.appendingPathComponent("img_\(i).png")
                try? pngData.write(to: url)
                paths.append(url.path)
            }
        }
        return (folder, paths)
    }

    private func cleanup(folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - 측정 helper

    /// 단일 iteration — `CGImageSourceCreateImageAtIndex` + `dataProvider.data` 강제 pixel bytes 풀로드.
    /// `NSImage(contentsOfFile:)` 단독 호출은 lazy — 단위 테스트 환경에서 backing store 미잡힘 (SwiftUI render 단계 누락).
    /// CGImageSource path 는 풀 디코딩 강제 → 실제 *SwiftUI Image(nsImage:) render 시점 메모리* 와 동등 수준 시뮬레이션.
    /// 로드한 Data 배열 lifetime = pool 내부 → pool 종료 시 회수.
    private func measureDirectLoad(paths: [String]) -> Int64 {
        var delta: Int64 = 0
        autoreleasepool {
            let before = MemoryProbe.residentBytes()

            var pixelData: [Data] = []
            pixelData.reserveCapacity(paths.count)
            let opts: CFDictionary = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldAllowFloat: false
            ] as CFDictionary
            for path in paths {
                let url = URL(fileURLWithPath: path)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, opts),
                      let provider = cgImage.dataProvider,
                      let data = provider.data as Data?
                else { continue }
                pixelData.append(data)  // RGBA bytes 강제 잡힘 — 풀해상도 = pixelW × pixelH × 4 (≈ 8MB × 50 ≈ 400MB peak)
            }

            let after = MemoryProbe.residentBytes()
            delta = Int64(after) - Int64(before)
            _ = pixelData.count  // suppress unused warning
        }
        return delta
    }

    // MARK: - Tests

    @Test("baseline — 50 images NSImage direct load + force decode (5-iter mean)")
    func baseline_directLoad() async {
        let (folder, paths) = createTestImages(count: 50)
        defer { cleanup(folder: folder) }

        var deltas: [Int64] = []
        for iter in 1...5 {
            let delta = measureDirectLoad(paths: paths)
            deltas.append(delta)
            let deltaMB = Double(delta) / 1_048_576
            print(String(format: "[memory-snapshot baseline] iter=%d delta=%+.1fMB", iter, deltaMB))
        }

        let avg = deltas.reduce(0, +) / Int64(deltas.count)
        let avgMB = Double(avg) / 1_048_576
        print(String(format: "[memory-snapshot baseline] avg-delta=%+.1fMB (5-iter mean, n=%d, pattern=direct-load)", avgMB, paths.count))

        // 베이스라인 단계 — 임계 assert X. Phase 3 / 10 회귀 단계에서 박음.
        #expect(true)
    }

    /// TASK-082 Phase 3 — `ThumbnailCache.shared.thumbnail(for:targetSize:)` 경유 패턴 측정.
    /// 동일 50건 path / 36×32pt target → CGImageSource 다운스케일 후 NSImage 보유.
    /// 풀해상도 RGBA bytes 강제 잡지 않음 — 다운스케일된 NSImage instance + NSCache 메모리만.
    /// 베이스라인 (`baseline_directLoad` 약 1576MB peak) 대비 90%+ 감소 기대.
    private func measureViaThumbnailCache(paths: [String]) -> Int64 {
        var delta: Int64 = 0
        let target = NSSize(width: 36, height: 32)
        autoreleasepool {
            // 측정 격리 — 이전 iteration 캐시 잔존이 다음 측정 영향 X.
            ThumbnailCache.shared.evictAll()
            let before = MemoryProbe.residentBytes()

            var images: [NSImage] = []
            images.reserveCapacity(paths.count)
            for path in paths {
                if let img = ThumbnailCache.shared.thumbnail(for: path, targetSize: target) {
                    images.append(img)
                }
            }

            let after = MemoryProbe.residentBytes()
            delta = Int64(after) - Int64(before)
            _ = images.count
        }
        return delta
    }

    @Test("Phase 3 — 50 images ThumbnailCache (5-iter mean)")
    func phase3_thumbnailCache() async {
        let (folder, paths) = createTestImages(count: 50)
        defer { cleanup(folder: folder) }

        var deltas: [Int64] = []
        for iter in 1...5 {
            let delta = measureViaThumbnailCache(paths: paths)
            deltas.append(delta)
            let deltaMB = Double(delta) / 1_048_576
            print(String(format: "[memory-snapshot phase3] iter=%d delta=%+.1fMB", iter, deltaMB))
        }

        let avg = deltas.reduce(0, +) / Int64(deltas.count)
        let avgMB = Double(avg) / 1_048_576
        print(String(format: "[memory-snapshot phase3] avg-delta=%+.1fMB (5-iter mean, n=%d, pattern=thumbnail-cache)", avgMB, paths.count))

        #expect(true)
    }
}
