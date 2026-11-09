import Foundation

/// What the Quick Wheel shows.
public enum WheelSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case favoritesThenFrequent
    case favorites
    case frequent

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .favoritesThenFrequent: return "Favorites, then most used"
        case .favorites: return "Favorites only"
        case .frequent: return "Most used"
        }
    }
}

/// Pure geometry and selection logic for the Quick Wheel (unit-tested).
public enum WheelLayout {
    public static let slotRange = 4...12
    public static let defaultSlots = 8

    /// Chooses up to `slots` items for the wheel.
    public static func items(from library: [LaunchItem], source: WheelSource, slots: Int) -> [LaunchItem] {
        let count = slotRange.clamp(slots)
        let favorites = library.filter(\.isPinned)
        let frequent = library
            .filter { $0.openCount > 0 }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.openCount != rhs.element.openCount { return lhs.element.openCount > rhs.element.openCount }
                let l = lhs.element.lastOpenedAt ?? .distantPast, r = rhs.element.lastOpenedAt ?? .distantPast
                if l != r { return l > r }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var result: [LaunchItem]
        switch source {
        case .favorites:
            result = favorites
        case .frequent:
            result = frequent
        case .favoritesThenFrequent:
            result = favorites
            // Top up with most-used, then the rest of the library, so the wheel is useful from day one.
            for item in frequent + library where result.count < count && !result.contains(where: { $0.id == item.id }) {
                result.append(item)
            }
        }
        return Array(result.prefix(count))
    }

    /// Angle (radians, 0 = top, clockwise) of the centre of slot `index`.
    public static func centerAngle(of index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        return 2 * .pi * Double(index) / Double(count)
    }

    /// The slot in the direction of a pointer offset from the wheel centre.
    /// `dx` grows to the right and `dy` grows **upwards** (AppKit screen coordinates).
    /// Returns `nil` inside the dead zone so the pointer can rest in the middle.
    public static func slot(dx: Double, dy: Double, count: Int, deadZone: Double = 36) -> Int? {
        guard count > 0, (dx * dx + dy * dy).squareRoot() >= deadZone else { return nil }
        var angle = atan2(dx, dy) // 0 at top, clockwise positive
        if angle < 0 { angle += 2 * .pi }
        let width = 2 * .pi / Double(count)
        return Int((angle + width / 2) / width) % count
    }

    /// What happens when the user lets go of the shortcut's modifier keys (for ⌥Tab, the ⌥ key).
    ///
    /// Carbon reports the shortcut "released" when the *main* key (Tab) comes up, which is
    /// usually long before ⌥ is released, so the wheel follows the modifiers instead.
    public enum HoldOutcome: Equatable, Sendable {
        /// Open or switch to this slot.
        case open(Int)
        /// Held for a while without choosing anything: close the wheel.
        case cancel
        /// A quick tap: keep the wheel open for clicking or the keyboard.
        case stayOpen
    }

    /// Holds shorter than this count as a tap.
    public static let tapThreshold: Double = 0.35

    public static func holdOutcome(highlighted: Int?, heldFor seconds: Double) -> HoldOutcome {
        if let highlighted { return .open(highlighted) }
        return seconds > tapThreshold ? .cancel : .stayOpen
    }
}
