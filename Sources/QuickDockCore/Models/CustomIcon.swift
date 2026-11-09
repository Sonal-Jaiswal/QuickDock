import Foundation

/// A user-chosen icon that replaces an item's native icon.
public enum CustomIcon: Equatable, Hashable, Sendable {
    /// An SF Symbol drawn on a tinted tile.
    case symbol(name: String, tint: IconTint)
    /// A PNG image stored in QuickDock's Icons directory.
    case image(fileName: String)
}

extension CustomIcon: Codable {
    private enum CodingKeys: String, CodingKey { case type, symbol, tint, fileName }
    private enum Kind: String, Codable { case symbol, image }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .symbol:
            let name = try container.decode(String.self, forKey: .symbol)
            let tint = try container.decodeIfPresent(IconTint.self, forKey: .tint) ?? .blue
            self = .symbol(name: name, tint: tint)
        case .image:
            self = .image(fileName: try container.decode(String.self, forKey: .fileName))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let name, let tint):
            try container.encode(Kind.symbol, forKey: .type)
            try container.encode(name, forKey: .symbol)
            try container.encode(tint, forKey: .tint)
        case .image(let fileName):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(fileName, forKey: .fileName)
        }
    }
}

/// Tile colors for symbol icons. Stored by name so the palette can evolve.
public enum IconTint: String, Codable, CaseIterable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, graphite

    public var displayName: String { rawValue.capitalized }

    /// sRGB components (0–1) for the tile's base color.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blue: return (0.04, 0.48, 1.00)
        case .indigo: return (0.35, 0.34, 0.84)
        case .purple: return (0.69, 0.32, 0.87)
        case .pink: return (1.00, 0.18, 0.33)
        case .red: return (1.00, 0.27, 0.23)
        case .orange: return (1.00, 0.58, 0.00)
        case .yellow: return (0.95, 0.75, 0.05)
        case .green: return (0.20, 0.78, 0.35)
        case .teal: return (0.19, 0.69, 0.78)
        case .graphite: return (0.40, 0.42, 0.46)
        }
    }

    /// A stable tint derived from text, used for website monogram tiles.
    public static func stable(for text: String) -> IconTint {
        let palette: [IconTint] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal, .red]
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in text.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

/// SF Symbols offered in the icon picker. Curated to those available on macOS 13.
public enum IconSymbols {
    public static let all: [String] = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "globe",
        "house.fill", "briefcase.fill", "folder.fill", "doc.text.fill", "book.fill", "bookmark.fill",
        "tray.full.fill", "archivebox.fill", "paperplane.fill", "envelope.fill", "bubble.left.fill", "phone.fill",
        "calendar", "clock.fill", "alarm.fill", "music.note", "headphones", "film.fill",
        "camera.fill", "photo.fill", "paintbrush.fill", "pencil", "hammer.fill", "wrench.and.screwdriver.fill",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "cpu.fill", "server.rack", "externaldrive.fill", "icloud.fill",
        "cart.fill", "creditcard.fill", "chart.bar.fill", "chart.pie.fill", "graduationcap.fill", "lightbulb.fill",
        "gamecontroller.fill", "airplane", "car.fill", "map.fill", "person.fill", "person.2.fill",
    ]
}
