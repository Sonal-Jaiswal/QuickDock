// Composes website/public/og-image.png (1200×630) from the real app icon and a real
// launcher screenshot. Usage: swiftc scripts/generate-og-image.swift -o /tmp/og && /tmp/og
import AppKit

let width = 1200, height = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 1),
                    NSColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: 1)])!.draw(in: bounds, angle: -60)
NSGradient(colors: [NSColor(srgbRed: 0.25, green: 0.45, blue: 1, alpha: 0.35), .clear])!
    .draw(fromCenter: NSPoint(x: 880, y: 300), radius: 0, toCenter: NSPoint(x: 880, y: 300), radius: 520, options: [])

if let icon = NSImage(contentsOfFile: "Resources/AppIcon/AppIcon-1024.png") {
    icon.draw(in: NSRect(x: 56, y: 400, width: 156, height: 156))
}
func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, at point: NSPoint, width: CGFloat = 520) {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 4
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: style,
    ]).draw(in: NSRect(x: point.x, y: point.y, width: width, height: size * 2.6))
}
text("QuickDock", size: 64, weight: .bold, alpha: 1, at: NSPoint(x: 64, y: 230))
text("Your Mac, one click away.", size: 30, weight: .medium, alpha: 0.85, at: NSPoint(x: 66, y: 206))
text("A free, private launcher for your apps, files, folders and websites.", size: 22, weight: .regular,
     alpha: 0.6, at: NSPoint(x: 66, y: 76), width: 470)

if let shot = NSImage(contentsOfFile: "website/public/screenshots/launcher-dark.png") {
    let w: CGFloat = 600, h = w * shot.size.height / shot.size.width
    let rect = NSRect(x: 560, y: (CGFloat(height) - h) / 2, width: w, height: h)
    let shadow = NSShadow(); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6); shadow.set()
    shot.draw(in: rect)
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "website/public/og-image.png"))
print("✓ website/public/og-image.png")
