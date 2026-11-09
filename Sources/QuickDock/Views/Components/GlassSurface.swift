import AppKit
import SwiftUI

/// A translucent "dark glass" surface for borderless windows: Liquid Glass on macOS 26+,
/// a behind-window vibrancy material (masked to the shape) on earlier versions.
struct GlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.tintColor = GlassSurface.tint
            return glass
        }
        #endif
        let effect = MaskedEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.cornerRadius = cornerRadius
        return effect
    }

    func updateNSView(_ view: NSView, context: Context) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            return
        }
        #endif
        (view as? MaskedEffectView)?.cornerRadius = cornerRadius
    }

    /// Deep tint in Dark Mode, soft frost in Light Mode, for legible content over any wallpaper.
    static let tint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.05, alpha: 0.5)
            : NSColor(calibratedWhite: 1.0, alpha: 0.55)
    }
}

/// `NSVisualEffectView` whose mask follows a rounded rectangle (or circle) as it resizes.
final class MaskedEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 16 { didSet { needsLayout = true } }

    override func layout() {
        super.layout()
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        guard bounds.width > 0, bounds.height > 0 else { return }
        maskImage = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }
}
