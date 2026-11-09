#!/usr/bin/env swift
// Renders QuickDock's app icon (1024×1024 PNG) with Core Graphics.
// Usage: swift scripts/generate-icon.swift <output.png>
//
// Design: a dark "glass" squircle following Apple's icon grid, with a frosted
// dock shelf holding three tiles — a launcher, one click away.

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let cg = context.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func linear(_ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    cg.drawLinearGradient(gradient, start: from, end: to, options: [])
    cg.restoreGState()
}

// Apple's macOS icon grid: 824pt body centred in 1024 with ~185pt corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body, radius: 185)

// Drop shadow.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.35))
cg.addPath(bodyPath)
cg.setFillColor(color(0.08, 0.09, 0.13))
cg.fillPath()
cg.restoreGState()

// Deep glass background.
linear(bodyPath, [color(0.20, 0.23, 0.33), color(0.07, 0.08, 0.12)],
       from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))

// Soft coloured glow behind the shelf.
cg.saveGState()
cg.addPath(bodyPath)
cg.clip()
let glow = CGGradient(colorsSpace: space, colors: [color(0.30, 0.50, 1.0, 0.45), color(0.30, 0.50, 1.0, 0)] as CFArray, locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                      endCenter: CGPoint(x: 512, y: 470), endRadius: 420, options: [])
cg.restoreGState()

// Top sheen.
cg.saveGState()
cg.addPath(bodyPath)
cg.clip()
linear(bodyPath, [color(1, 1, 1, 0.12), color(1, 1, 1, 0.0)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: 560))
cg.restoreGState()

// Hairline border.
cg.saveGState()
cg.addPath(squircle(body.insetBy(dx: 2, dy: 2), radius: 183))
cg.setStrokeColor(color(1, 1, 1, 0.16))
cg.setLineWidth(4)
cg.strokePath()
cg.restoreGState()

// Frosted shelf (the "dock").
let shelf = CGRect(x: 212, y: 330, width: 600, height: 300)
let shelfPath = squircle(shelf, radius: 92)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0, 0, 0, 0.45))
cg.addPath(shelfPath)
cg.setFillColor(color(1, 1, 1, 0.10))
cg.fillPath()
cg.restoreGState()
linear(shelfPath, [color(1, 1, 1, 0.22), color(1, 1, 1, 0.06)], from: CGPoint(x: 0, y: shelf.maxY), to: CGPoint(x: 0, y: shelf.minY))
cg.saveGState()
cg.addPath(squircle(shelf.insetBy(dx: 2, dy: 2), radius: 90))
cg.setStrokeColor(color(1, 1, 1, 0.30))
cg.setLineWidth(4)
cg.strokePath()
cg.restoreGState()

// Three tiles.
let tileSize: CGFloat = 132
let gap: CGFloat = 44
let tileColors: [(CGColor, CGColor)] = [
    (color(0.38, 0.66, 1.0), color(0.05, 0.42, 1.0)),
    (color(1.0, 0.72, 0.30), color(1.0, 0.50, 0.05)),
    (color(0.50, 0.90, 0.60), color(0.15, 0.72, 0.38)),
]
let startX = shelf.midX - (tileSize * 3 + gap * 2) / 2
for (index, colors) in tileColors.enumerated() {
    let rect = CGRect(x: startX + CGFloat(index) * (tileSize + gap), y: shelf.midY - tileSize / 2 - 6,
                      width: tileSize, height: tileSize)
    let path = squircle(rect, radius: 34)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0, 0, 0, 0.35))
    cg.addPath(path)
    cg.setFillColor(colors.1)
    cg.fillPath()
    cg.restoreGState()
    linear(path, [colors.0, colors.1], from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))
    cg.saveGState()
    cg.addPath(squircle(rect.insetBy(dx: 1.5, dy: 1.5), radius: 33))
    cg.setStrokeColor(color(1, 1, 1, 0.35))
    cg.setLineWidth(3)
    cg.strokePath()
    cg.restoreGState()
}

// "One click" indicator dot under the centre tile.
cg.setFillColor(color(1, 1, 1, 0.85))
cg.fillEllipse(in: CGRect(x: 512 - 11, y: shelf.minY + 26, width: 22, height: 22))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
