import SwiftUI
import QuickDockCore

/// Draws an item's icon: the native icon for apps, files and folders; a custom
/// image; or a tile with a symbol (actions, symbol icons) or monogram (websites).
struct ItemIconView: View {
    let item: LaunchItem
    let size: CGFloat
    @EnvironmentObject private var icons: IconProvider

    var body: some View {
        Group {
            if let image = icons.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                tile
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tile: some View {
        switch (item.customIcon, item.target) {
        case (.symbol(let name, let tint)?, _):
            SymbolTile(symbol: name, tint: tint, size: size)
        case (_, .website(let url)):
            MonogramTile(text: WebAddress.displayName(for: url), size: size)
        case (_, .action(let action)):
            SymbolTile(symbol: action.kind.symbolName, tint: Self.tint(for: action.kind), size: size)
        default:
            SymbolTile(symbol: "questionmark", tint: .graphite, size: size)
        }
    }

    static func tint(for action: PredefinedAction) -> IconTint {
        switch action {
        case .copySnippet: return .indigo
        case .composeEmail: return .blue
        case .startScreenSaver: return .purple
        case .takeScreenshot: return .graphite
        case .missionControl: return .teal
        case .systemSettings: return .graphite
        case .quickDockSettings: return .indigo
        }
    }
}

extension IconTint {
    var color: Color { Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1) }
}

/// The rounded "squircle" used for generated icons, sized like macOS app icons
/// (which leave a small margin inside their canvas).
struct IconTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.09
        let tileRect = rect.insetBy(dx: inset, dy: inset)
        return RoundedRectangle(cornerRadius: tileRect.width * 0.23, style: .continuous).path(in: tileRect)
    }
}

struct SymbolTile: View {
    let symbol: String
    let tint: IconTint
    let size: CGFloat

    var body: some View {
        ZStack {
            IconTileShape()
                .fill(LinearGradient(colors: [tint.color.opacity(0.85), tint.color],
                                     startPoint: .top, endPoint: .bottom))
            IconTileShape()
                .strokeBorderCompat(Color.white.opacity(0.18), lineWidth: max(0.5, size / 96))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: size / 64, y: size / 96)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: size / 40, y: size / 80)
    }
}

struct MonogramTile: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let tint = IconTint.stable(for: text)
        ZStack {
            IconTileShape()
                .fill(LinearGradient(colors: [tint.color.opacity(0.85), tint.color], startPoint: .top, endPoint: .bottom))
            IconTileShape()
                .strokeBorderCompat(Color.white.opacity(0.18), lineWidth: max(0.5, size / 96))
            Text(String(text.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Image(systemName: "globe")
                .font(.system(size: size * 0.16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .offset(x: size * 0.22, y: size * 0.22)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: size / 40, y: size / 80)
    }
}

extension Shape {
    /// An inset stroke that stays inside the shape (works on macOS 13).
    func strokeBorderCompat(_ color: Color, lineWidth: CGFloat) -> some View {
        self.stroke(color, lineWidth: lineWidth).clipShape(self)
    }
}
