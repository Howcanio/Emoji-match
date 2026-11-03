#!/usr/bin/env swift
// Draws the 1024pt app icon with CoreGraphics. The artwork is entirely hand-drawn, with no
// bitmap emoji glyphs in it. Usage: swift scripts/generate_app_icon.swift <output.png>
import AppKit

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

let background = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [rgb(1.0, 0.42, 0.62, 1), rgb(0.48, 0.36, 1.0, 1)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

let centers = [CGPoint(x: 262, y: 700), CGPoint(x: 762, y: 610), CGPoint(x: 400, y: 270)]

// Glowing string
let string = CGMutablePath()
string.addLines(between: centers)
context.setLineCap(.round)
context.setLineJoin(.round)
for (width, alpha) in [(CGFloat(92), CGFloat(0.22)), (58, 0.4), (26, 1)] {
    context.addPath(string)
    context.setStrokeColor(rgb(1, 1, 1, alpha))
    context.setLineWidth(width)
    context.strokePath()
}

// Three identical smiling tiles
for center in centers {
    let tile = CGRect(x: center.x - 165, y: center.y - 165, width: 330, height: 330)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0.2, 0.05, 0.4, 0.4))
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 80, cornerHeight: 80, transform: nil))
    context.setFillColor(rgb(1, 0.98, 0.94, 1))
    context.fillPath()
    context.restoreGState()

    let face = tile.insetBy(dx: 42, dy: 42)
    context.setFillColor(rgb(1, 0.8, 0.2, 1))
    context.fillEllipse(in: face)
    context.setFillColor(rgb(0.3, 0.17, 0.08, 1))
    for dx in [CGFloat(-52), 52] {
        context.fillEllipse(in: CGRect(x: center.x + dx - 19, y: center.y + 20, width: 38, height: 52))
    }
    context.setStrokeColor(rgb(0.3, 0.17, 0.08, 1))
    context.setLineWidth(20)
    context.addArc(center: CGPoint(x: center.x, y: center.y - 8), radius: 76, startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
    context.strokePath()
}

let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
