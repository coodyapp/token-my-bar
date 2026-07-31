#!/usr/bin/env swift
//
// Renders the app icon — the red bar-chart mark on the site's near-black
// squircle — at every size the .icns needs. Re-runnable generator: run it,
// then fold the iconset into the AppIcon.icns that package.sh copies into
// the bundle:
//
//   swift Scripts/generate-app-icon.swift Scripts
//   iconutil -c icns Scripts/AppIcon.iconset -o Scripts/AppIcon.icns
//   rm -rf Scripts/AppIcon.iconset
//
// Every size is drawn from the vector geometry rather than downsampled from
// 1024, so the bars stay crisp down at 16 pt. Colors track apps/www: the
// neutral-950 background (#0a0a0a) and the rgba(229,72,77) hero red.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Apple's macOS icon grid: 824x824 of live area centered on a 1024 canvas,
// leaving the margin the drop shadow lives in.
let canvas = 1024.0
let liveInset = 100.0
let live = CGRect(x: liveInset, y: liveInset, width: canvas - liveInset * 2, height: canvas - liveInset * 2)
let cornerRadius = 185.4

let bodyTop = CGColor(srgbRed: 0.118, green: 0.118, blue: 0.133, alpha: 1)
let bodyBottom = CGColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
let glowColor = CGColor(srgbRed: 0.898, green: 0.282, blue: 0.302, alpha: 0.38)
let barTop = CGColor(srgbRed: 1.0, green: 0.365, blue: 0.384, alpha: 1)
let barBottom = CGColor(srgbRed: 0.847, green: 0.239, blue: 0.263, alpha: 1)

// Three ascending bars on a shared baseline, filling ~60% of the live area so
// the gaps survive the 16 pt rendering. Ascending bars carry their visual mass
// low and to the right, so the block is nudged up and left of dead center.
let barWidth = 132.0
let barGap = 48.0
let barRadius = 36.0
let baseline = 284.0
let barHeights = [272.0, 380.0, 488.0]
let blockOffsetX = -14.0

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func squircle(_ rect: CGRect) -> CGPath {
    // SwiftUI hands back Apple's continuous corner curve; a plain rounded
    // rect reads visibly boxier next to system icons.
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect).cgPath
}

func gradient(from: CGColor, to: CGColor) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: [from, to] as CFArray, locations: [0, 1])!
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / canvas
    ctx.scaleBy(x: scale, y: scale)

    let body = squircle(live)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.32))
    ctx.addPath(body)
    ctx.setFillColor(bodyBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    ctx.drawLinearGradient(
        gradient(from: bodyTop, to: bodyBottom),
        start: CGPoint(x: 0, y: live.maxY),
        end: CGPoint(x: 0, y: live.minY),
        options: []
    )

    // The hero's radial glow: an ellipse hanging off the top edge, drawn as a
    // circular gradient under a vertical stretch.
    let glowCenterY = 980.0
    let glowRadiusX = 360.0
    let glowRadiusY = 640.0
    ctx.saveGState()
    ctx.translateBy(x: canvas / 2, y: glowCenterY)
    ctx.scaleBy(x: 1, y: glowRadiusY / glowRadiusX)
    ctx.drawRadialGradient(
        gradient(from: glowColor, to: glowColor.copy(alpha: 0)!),
        startCenter: .zero, startRadius: 0,
        endCenter: .zero, endRadius: glowRadiusX,
        options: []
    )
    ctx.restoreGState()

    let blockWidth = barWidth * 3 + barGap * 2
    var barX = (canvas - blockWidth) / 2 + blockOffsetX
    let bars = CGMutablePath()
    for height in barHeights {
        bars.addPath(CGPath(
            roundedRect: CGRect(x: barX, y: baseline, width: barWidth, height: height),
            cornerWidth: barRadius, cornerHeight: barRadius, transform: nil
        ))
        barX += barWidth + barGap
    }
    ctx.addPath(bars)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(from: barTop, to: barBottom),
        start: CGPoint(x: 0, y: baseline + barHeights.max()!),
        end: CGPoint(x: 0, y: baseline),
        options: []
    )
    ctx.restoreGState()

    // Top-lit rim, brightest at the top edge and gone by the bottom.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.addPath(body)
    ctx.setLineWidth(6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(
            from: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
            to: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.02)
        ),
        start: CGPoint(x: 0, y: live.maxY),
        end: CGPoint(x: 0, y: live.minY),
        options: []
    )
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Failed to write \(path)")
    }
    print("wrote \(path)")
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: base), to: "\(iconset)/icon_\(base)x\(base).png")
    writePNG(render(pixels: base * 2), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
}
