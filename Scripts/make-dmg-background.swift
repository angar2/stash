#!/usr/bin/env swift
// dmg 설치 창 배경 이미지를 렌더하는 스크립트 — 크림색 바탕 + 앱 아이콘과 Applications 사이 화살표

import AppKit
import Foundation

// ── 기준 수치 ────────────────────────────────────────────
// dmg 창 크기(654×444)에서 제목표시줄 22 를 뺀 값 = 콘텐츠 영역 = 배경 이미지 크기.
// 이 값이 어긋나면 배경이 잘리거나 남는 여백이 생긴다. build-dmg.sh 의 창 설정 값과 한 쌍이다.
//
// **1x 한 장만 낸다.** Retina 용 2x 를 tiff 로 묶어 넣었더니 Finder 가 2x 그림을 축소하지 않고
// 그대로 그려, 창에는 그림의 좌상단 654×422 조각만 들어오고 화살표가 오른쪽 밖으로 밀려났다(실측).
// 널리 쓰이는 배포본들도 1x 단일 PNG 를 쓴다. 단색 배경 + 단순 도형이라 확대 손실이 눈에 띄지 않는다.
let width: CGFloat = 654
let height: CGFloat = 422

// 아이콘 좌표 — build-dmg.sh 가 Finder 에 지정하는 값과 동일해야 화살표가 두 아이콘 사이에 온다.
// Finder 좌표계는 좌상단 원점이라 AppKit(좌하단 원점)으로 그릴 때 y 를 뒤집는다.
let appIconX: CGFloat = 197
let applicationsIconX: CGFloat = 473
let iconYFromTop: CGFloat = 195

// 배색 — 앱 아이콘 실측값 기준. 바탕은 아이콘 배(크림 #F0E5D0)를 밝게 편 색,
// 화살표는 아이콘 바탕(남색 #384E62 ~ #273749)의 중간값. 라이트 기준으로 대비를 맞춘다
// (dmg 배경은 시스템 외관을 따라가지 않아 다크 모드에서도 이 색 그대로 뜬다).
let backgroundColor = NSColor(srgbRed: 0xF4 / 255, green: 0xED / 255, blue: 0xE0 / 255, alpha: 1)
let arrowColor = NSColor(srgbRed: 0x2F / 255, green: 0x42 / 255, blue: 0x56 / 255, alpha: 1)

let arrowLineWidth: CGFloat = 10
let arrowHalfLength: CGFloat = 34
let arrowHeadDepth: CGFloat = 23
let arrowHeadHalfHeight: CGFloat = 22

// ── 렌더 ─────────────────────────────────────────────────
func drawBackground() {
    backgroundColor.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let centerX = (appIconX + applicationsIconX) / 2
    let centerY = height - iconYFromTop  // Finder 좌상단 원점 → AppKit 좌하단 원점
    let tipX = centerX + arrowHalfLength
    let tailX = centerX - arrowHalfLength
    let headBackX = tipX - arrowHeadDepth

    let path = NSBezierPath()
    path.move(to: NSPoint(x: tailX, y: centerY))
    path.line(to: NSPoint(x: tipX, y: centerY))
    path.move(to: NSPoint(x: headBackX, y: centerY - arrowHeadHalfHeight))
    path.line(to: NSPoint(x: tipX, y: centerY))
    path.line(to: NSPoint(x: headBackX, y: centerY + arrowHeadHalfHeight))

    path.lineWidth = arrowLineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    arrowColor.setStroke()
    path.stroke()
}

/// 지정 배율로 렌더해 PNG 로 저장한다. scale=2 면 픽셀 수만 2배가 되고 그리는 좌표계는 그대로다.
func writePNG(to url: URL, scale: CGFloat) throws {
    let pixelsWide = Int(width * scale)
    let pixelsHigh = Int(height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "make-dmg-background", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "비트맵 생성 실패 (\(pixelsWide)×\(pixelsHigh))"])
    }
    rep.size = NSSize(width: width, height: height)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "make-dmg-background", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "그래픽 컨텍스트 생성 실패"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-dmg-background", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "PNG 인코딩 실패"])
    }
    try data.write(to: url)
    print("  \(url.lastPathComponent) — \(pixelsWide)×\(pixelsHigh)")
}

// ── 진입점 ───────────────────────────────────────────────
guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("사용법: swift Scripts/make-dmg-background.swift <출력 디렉터리>\n".data(using: .utf8)!)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    print("dmg 배경 렌더 → \(outputDirectory.path)")
    try writePNG(to: outputDirectory.appendingPathComponent("background.png"), scale: 1)
} catch {
    FileHandle.standardError.write("✗ 배경 렌더 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
