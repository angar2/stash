// StashLogoMark 땅콩 틀 계산과 MenuBarIcon 이미지 규격 정합 회귀 차단 (TASK-105)
import AppKit
import Testing
@testable import stash

@MainActor
@Suite("StashLogoMark (TASK-105)")
struct StashLogoMarkTests {
    @Test("TASK-105 — 팝오버 머리 18 → 땅콩 틀 18×9, 온보딩 키캡 24 → 24×12")
    func markHeightIsHalfOfWidth() {
        #expect(StashLogoMark.markHeight(forWidth: 18) == 9)
        #expect(StashLogoMark.markHeight(forWidth: 24) == 12)
    }

    @Test("TASK-105 — 이동 후 땅콩 윗변이 틀 윗변과 일치 (투명 여백이 틀 밖으로 빠짐)", arguments: [18.0, 24.0])
    func markTopAlignsWithFrameTop(width: CGFloat) {
        let frameHeight = StashLogoMark.markHeight(forWidth: width)
        // 정사각 이미지를 틀 가운데 두면 이미지 윗변 = 틀 윗변 - (width - frameHeight) / 2
        let imageTop = -(width - frameHeight) / 2 + StashLogoMark.verticalOffset(forWidth: width)
        let markTop = imageTop + StashLogoMark.markTop / StashLogoMark.imageSide * width
        #expect(abs(markTop) < 0.0001)
    }

    @Test("TASK-105 — MenuBarIcon@2x 의 땅콩 위치 = StashLogoMark 상수 (가로 꽉 참 · 위 10 · 높이 22)")
    func assetMatchesMarkConstants() throws {
        let image = try #require(NSImage(named: "MenuBarIcon"))
        let side = Int(StashLogoMark.imageSide)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = NSSize(width: side / 2, height: side / 2)   // 22pt @2x → 44px 표현 선택
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        context?.imageInterpolation = .none
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()

        var rows: [Int] = []
        var cols: [Int] = []
        for y in 0..<side {
            for x in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                rows.append(y)
                cols.append(x)
            }
        }
        #expect(cols.min() == 0)
        #expect(cols.max() == side - 1)
        #expect(rows.min() == Int(StashLogoMark.markTop))
        #expect(rows.max() == Int(StashLogoMark.markTop + StashLogoMark.markHeight) - 1)
    }
}
