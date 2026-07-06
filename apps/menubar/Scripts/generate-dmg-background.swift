#!/usr/bin/env swift
//
// Renders the DMG installer window background ("Drag App to Applications")
// at 1x and 2x. One-off generator: run it, then combine the PNGs into the
// retina TIFF that package.sh hands to create-dmg:
//
//   swift Scripts/generate-dmg-background.swift Scripts
//   tiffutil -cathidpicheck Scripts/dmg-background.png Scripts/dmg-background@2x.png \
//     -out Scripts/dmg-background.tiff
//   rm Scripts/dmg-background.png Scripts/dmg-background@2x.png
//
// Canvas is 655x420 pt to match the create-dmg window size in package.sh;
// the arrow row sits at the icon centers (y 240 from the top, icons at
// x 165 and x 490).

import AppKit
import UniformTypeIdentifiers

let width = 655.0
let height = 420.0

let background = CGColor(srgbRed: 0.965, green: 0.957, blue: 0.937, alpha: 1)
let titleColor = NSColor(srgbRed: 0.24, green: 0.22, blue: 0.19, alpha: 1)
let arrowColor = CGColor(srgbRed: 0.55, green: 0.17, blue: 0.12, alpha: 1)

func render(scale: CGFloat) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: Int(width * scale),
        height: Int(height * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: scale, y: scale)

    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Title, centered near the top. CoreGraphics origin is bottom-left, so
    // top-relative y coordinates are flipped through `height`.
    let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let title = NSAttributedString(
        string: "Drag App to Applications",
        attributes: [.font: font, .foregroundColor: titleColor]
    )
    let line = CTLineCreateWithAttributedString(title)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (width - bounds.width) / 2, y: height - 84 - bounds.height / 2)
    CTLineDraw(line, ctx)

    // Arrow between the app icon (center x 165) and the Applications drop
    // link (center x 490), clear of the 128 pt icons on either side.
    let rowY = height - 240
    let tailX = 252.0
    let headX = 410.0
    let headLength = 14.0
    let headHalfWidth = 7.0

    ctx.setStrokeColor(arrowColor)
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: tailX, y: rowY))
    ctx.addLine(to: CGPoint(x: headX - headLength, y: rowY))
    ctx.strokePath()

    ctx.setFillColor(arrowColor)
    ctx.move(to: CGPoint(x: headX, y: rowY))
    ctx.addLine(to: CGPoint(x: headX - headLength, y: rowY + headHalfWidth))
    ctx.addLine(to: CGPoint(x: headX - headLength, y: rowY - headHalfWidth))
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String, dpi: Int) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let properties = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
    ] as CFDictionary
    CGImageDestinationAddImage(dest, image, properties)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Failed to write \(path)")
    }
    print("wrote \(path)")
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
writePNG(render(scale: 1), to: "\(outDir)/dmg-background.png", dpi: 72)
writePNG(render(scale: 2), to: "\(outDir)/dmg-background@2x.png", dpi: 144)
