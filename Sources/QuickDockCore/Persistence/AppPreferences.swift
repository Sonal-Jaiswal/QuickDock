import Foundation
import Combine

public enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum IconSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// Icon edge length in points.
    public var points: Double {
        switch self {
        case .small: return 44
        case .medium: return 56
        case .large: return 72
        }
    }
}

/// Which filter the launcher shows when it opens.
public enum LauncherStartFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, favorites, lastUsed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "All Items"
        case .favorites: return "Favorites"
        case .lastUsed: return "Last Used Filter"
        }
    }
}

/// A portable copy of the user's preferences (used by export/import).
public struct PreferencesSnapshot: Codable, Equatable, Sendable {
    public var appearance: AppearanceMode
    public var hotKey: KeyCombo?
    public var gridColumns: Int
    public var maxVisibleRows: Int
    public var iconSize: IconSize
    public var showLabels: Bool
    public var closeAfterLaunch: Bool
    public var startFilter: LauncherStartFilter
    public var showFavoritesInMenu: Bool

    public init(appearance: AppearanceMode = .system,
                hotKey: KeyCombo? = .defaultLauncher,
                gridColumns: Int = AppPreferences.defaultColumns,
                maxVisibleRows: Int = AppPreferences.defaultRows,
                iconSize: IconSize = .medium,
                showLabels: Bool = true,
                closeAfterLaunch: Bool = true,
                startFilter: LauncherStartFilter = .all,
                showFavoritesInMenu: Bool = true) {
        self.appearance = appearance
        self.hotKey = hotKey
        self.gridColumns = gridColumns
        self.maxVisibleRows = maxVisibleRows
        self.iconSize = iconSize
        self.showLabels = showLabels
        self.closeAfterLaunch = closeAfterLaunch
        self.startFilter = startFilter
        self.showFavoritesInMenu = showFavoritesInMenu
    }

    /// Clamps numeric values into their supported ranges.
    public func sanitized() -> PreferencesSnapshot {
        var copy = self
        copy.gridColumns = AppPreferences.columnRange.clamp(gridColumns)
        copy.maxVisibleRows = AppPreferences.rowRange.clamp(maxVisibleRows)
        if let hotKey, case .invalid = hotKey.validate() { copy.hotKey = .defaultLauncher }
        return copy
    }
}

/// User preferences stored in `UserDefaults`.
///
/// Item data lives in `library.json` (see `LibraryStore`); only small settings live here.
@MainActor
public final class AppPreferences: ObservableObject {
    nonisolated public static let columnRange = 4...9
    nonisolated public static let rowRange = 2...6
    nonisolated public static let defaultColumns = 6
    nonisolated public static let defaultRows = 3

    enum Key {
        static let appearance = "appearance"
        static let hotKey = "hotKey"
        static let hotKeyDisabled = "hotKeyDisabled"
        static let gridColumns = "gridColumns"
        static let maxVisibleRows = "maxVisibleRows"
        static let iconSize = "iconSize"
        static let showLabels = "showLabels"
        static let closeAfterLaunch = "closeAfterLaunch"
        static let startFilter = "startFilter"
        static let lastFilter = "lastFilter"
        static let showFavoritesInMenu = "showFavoritesInMenu"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let all = [appearance, hotKey, hotKeyDisabled, gridColumns, maxVisibleRows, iconSize, showLabels,
                          closeAfterLaunch, startFilter, lastFilter, showFavoritesInMenu, hasCompletedOnboarding]
    }

    private let defaults: UserDefaults

    @Published public var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    /// `nil` means the global shortcut is turned off.
    @Published public var hotKey: KeyCombo? { didSet { storeHotKey() } }
    @Published public var gridColumns: Int {
        didSet {
            let clamped = Self.columnRange.clamp(gridColumns)
            if clamped != gridColumns { gridColumns = clamped; return }
            defaults.set(gridColumns, forKey: Key.gridColumns)
        }
    }
    @Published public var maxVisibleRows: Int {
        didSet {
            let clamped = Self.rowRange.clamp(maxVisibleRows)
            if clamped != maxVisibleRows { maxVisibleRows = clamped; return }
            defaults.set(maxVisibleRows, forKey: Key.maxVisibleRows)
        }
    }
    @Published public var iconSize: IconSize { didSet { defaults.set(iconSize.rawValue, forKey: Key.iconSize) } }
    @Published public var showLabels: Bool { didSet { defaults.set(showLabels, forKey: Key.showLabels) } }
    @Published public var closeAfterLaunch: Bool { didSet { defaults.set(closeAfterLaunch, forKey: Key.closeAfterLaunch) } }
    @Published public var startFilter: LauncherStartFilter { didSet { defaults.set(startFilter.rawValue, forKey: Key.startFilter) } }
    @Published public var lastFilter: ItemFilter { didSet { defaults.set(lastFilter.rawValue, forKey: Key.lastFilter) } }
    @Published public var showFavoritesInMenu: Bool { didSet { defaults.set(showFavoritesInMenu, forKey: Key.showFavoritesInMenu) } }
    @Published public var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        if defaults.bool(forKey: Key.hotKeyDisabled) {
            hotKey = nil
        } else if let data = defaults.data(forKey: Key.hotKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            if case .invalid = combo.validate() { hotKey = .defaultLauncher } else { hotKey = combo }
        } else {
            hotKey = .defaultLauncher
        }
        let storedColumns = defaults.object(forKey: Key.gridColumns) as? Int ?? Self.defaultColumns
        gridColumns = Self.columnRange.clamp(storedColumns)
        let storedRows = defaults.object(forKey: Key.maxVisibleRows) as? Int ?? Self.defaultRows
        maxVisibleRows = Self.rowRange.clamp(storedRows)
        iconSize = defaults.string(forKey: Key.iconSize).flatMap(IconSize.init(rawValue:)) ?? .medium
        showLabels = defaults.object(forKey: Key.showLabels) as? Bool ?? true
        closeAfterLaunch = defaults.object(forKey: Key.closeAfterLaunch) as? Bool ?? true
        startFilter = defaults.string(forKey: Key.startFilter).flatMap(LauncherStartFilter.init(rawValue:)) ?? .all
        lastFilter = defaults.string(forKey: Key.lastFilter).flatMap(ItemFilter.init(rawValue:)) ?? .all
        showFavoritesInMenu = defaults.object(forKey: Key.showFavoritesInMenu) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    private func storeHotKey() {
        if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: Key.hotKey)
            defaults.set(false, forKey: Key.hotKeyDisabled)
        } else {
            defaults.removeObject(forKey: Key.hotKey)
            defaults.set(true, forKey: Key.hotKeyDisabled)
        }
    }

    /// The filter the launcher should show when it opens.
    public var initialFilter: ItemFilter {
        switch startFilter {
        case .all: return .all
        case .favorites: return .favorites
        case .lastUsed: return lastFilter
        }
    }

    public var snapshot: PreferencesSnapshot {
        PreferencesSnapshot(appearance: appearance, hotKey: hotKey, gridColumns: gridColumns,
                            maxVisibleRows: maxVisibleRows, iconSize: iconSize, showLabels: showLabels,
                            closeAfterLaunch: closeAfterLaunch, startFilter: startFilter,
                            showFavoritesInMenu: showFavoritesInMenu)
    }

    public func apply(_ snapshot: PreferencesSnapshot) {
        let clean = snapshot.sanitized()
        appearance = clean.appearance
        hotKey = clean.hotKey
        gridColumns = clean.gridColumns
        maxVisibleRows = clean.maxVisibleRows
        iconSize = clean.iconSize
        showLabels = clean.showLabels
        closeAfterLaunch = clean.closeAfterLaunch
        startFilter = clean.startFilter
        showFavoritesInMenu = clean.showFavoritesInMenu
    }

    /// Restores every preference to its default. Items are not affected.
    /// Onboarding state is kept so users are not sent through setup again.
    public func resetToDefaults() {
        apply(PreferencesSnapshot())
        lastFilter = .all
    }

    /// Removes every stored key. Used by tests and by "Reset QuickDock".
    public func removeAllStoredValues() {
        for key in Key.all { defaults.removeObject(forKey: key) }
    }
}

extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
