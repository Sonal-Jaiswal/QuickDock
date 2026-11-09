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
    public var wheelHotKey: KeyCombo?
    public var wheelSource: WheelSource
    public var wheelSlots: Int
    public var showClipboardInWheel: Bool
    public var clipboardHistoryEnabled: Bool
    public var clipboardRemember: Bool
    public var clipboardLimit: Int

    public init(appearance: AppearanceMode = .system,
                hotKey: KeyCombo? = .defaultLauncher,
                gridColumns: Int = AppPreferences.defaultColumns,
                maxVisibleRows: Int = AppPreferences.defaultRows,
                iconSize: IconSize = .medium,
                showLabels: Bool = true,
                closeAfterLaunch: Bool = true,
                startFilter: LauncherStartFilter = .all,
                showFavoritesInMenu: Bool = true,
                wheelHotKey: KeyCombo? = .defaultWheel,
                wheelSource: WheelSource = .favoritesThenFrequent,
                wheelSlots: Int = WheelLayout.defaultSlots,
                showClipboardInWheel: Bool = true,
                clipboardHistoryEnabled: Bool = false,
                clipboardRemember: Bool = false,
                clipboardLimit: Int = ClipboardHistory.defaultLimit) {
        self.appearance = appearance
        self.hotKey = hotKey
        self.gridColumns = gridColumns
        self.maxVisibleRows = maxVisibleRows
        self.iconSize = iconSize
        self.showLabels = showLabels
        self.closeAfterLaunch = closeAfterLaunch
        self.startFilter = startFilter
        self.showFavoritesInMenu = showFavoritesInMenu
        self.wheelHotKey = wheelHotKey
        self.wheelSource = wheelSource
        self.wheelSlots = wheelSlots
        self.showClipboardInWheel = showClipboardInWheel
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.clipboardRemember = clipboardRemember
        self.clipboardLimit = clipboardLimit
    }

    private enum CodingKeys: String, CodingKey {
        case appearance, hotKey, gridColumns, maxVisibleRows, iconSize, showLabels, closeAfterLaunch, startFilter,
             showFavoritesInMenu, wheelHotKey, wheelSource, wheelSlots, showClipboardInWheel, clipboardHistoryEnabled,
             clipboardRemember, clipboardLimit
    }

    /// Tolerant decoding: settings added in later versions fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PreferencesSnapshot()
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? d.appearance
        hotKey = c.contains(.hotKey) ? try c.decodeIfPresent(KeyCombo.self, forKey: .hotKey) : d.hotKey
        gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? d.gridColumns
        maxVisibleRows = try c.decodeIfPresent(Int.self, forKey: .maxVisibleRows) ?? d.maxVisibleRows
        iconSize = try c.decodeIfPresent(IconSize.self, forKey: .iconSize) ?? d.iconSize
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? d.showLabels
        closeAfterLaunch = try c.decodeIfPresent(Bool.self, forKey: .closeAfterLaunch) ?? d.closeAfterLaunch
        startFilter = try c.decodeIfPresent(LauncherStartFilter.self, forKey: .startFilter) ?? d.startFilter
        showFavoritesInMenu = try c.decodeIfPresent(Bool.self, forKey: .showFavoritesInMenu) ?? d.showFavoritesInMenu
        wheelHotKey = c.contains(.wheelHotKey) ? try c.decodeIfPresent(KeyCombo.self, forKey: .wheelHotKey) : d.wheelHotKey
        wheelSource = try c.decodeIfPresent(WheelSource.self, forKey: .wheelSource) ?? d.wheelSource
        wheelSlots = try c.decodeIfPresent(Int.self, forKey: .wheelSlots) ?? d.wheelSlots
        showClipboardInWheel = try c.decodeIfPresent(Bool.self, forKey: .showClipboardInWheel) ?? d.showClipboardInWheel
        clipboardHistoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? d.clipboardHistoryEnabled
        clipboardRemember = try c.decodeIfPresent(Bool.self, forKey: .clipboardRemember) ?? d.clipboardRemember
        clipboardLimit = try c.decodeIfPresent(Int.self, forKey: .clipboardLimit) ?? d.clipboardLimit
    }

    /// Clamps numeric values into their supported ranges.
    public func sanitized() -> PreferencesSnapshot {
        var copy = self
        copy.gridColumns = AppPreferences.columnRange.clamp(gridColumns)
        copy.maxVisibleRows = AppPreferences.rowRange.clamp(maxVisibleRows)
        if let hotKey, case .invalid = hotKey.validate() { copy.hotKey = .defaultLauncher }
        if let wheelHotKey, case .invalid = wheelHotKey.validate() { copy.wheelHotKey = .defaultWheel }
        if copy.wheelHotKey != nil && copy.wheelHotKey == copy.hotKey { copy.wheelHotKey = nil }
        copy.wheelSlots = WheelLayout.slotRange.clamp(wheelSlots)
        copy.clipboardLimit = ClipboardHistory.limitRange.clamp(clipboardLimit)
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
        static let wheelHotKey = "wheelHotKey"
        static let wheelHotKeyDisabled = "wheelHotKeyDisabled"
        static let wheelSource = "wheelSource"
        static let wheelSlots = "wheelSlots"
        static let showClipboardInWheel = "showClipboardInWheel"
        static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
        static let clipboardRemember = "clipboardRemember"
        static let clipboardLimit = "clipboardLimit"
        static let all = [appearance, hotKey, hotKeyDisabled, gridColumns, maxVisibleRows, iconSize, showLabels,
                          closeAfterLaunch, startFilter, lastFilter, showFavoritesInMenu, hasCompletedOnboarding,
                          wheelHotKey, wheelHotKeyDisabled, wheelSource, wheelSlots, showClipboardInWheel,
                          clipboardHistoryEnabled, clipboardRemember, clipboardLimit]
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
    /// Shortcut for the Quick Wheel (hold to show, release to open). `nil` = off.
    @Published public var wheelHotKey: KeyCombo? {
        didSet { store(wheelHotKey, key: Key.wheelHotKey, disabledKey: Key.wheelHotKeyDisabled) }
    }
    @Published public var wheelSource: WheelSource { didSet { defaults.set(wheelSource.rawValue, forKey: Key.wheelSource) } }
    @Published public var wheelSlots: Int {
        didSet {
            let clamped = WheelLayout.slotRange.clamp(wheelSlots)
            if clamped != wheelSlots { wheelSlots = clamped; return }
            defaults.set(wheelSlots, forKey: Key.wheelSlots)
        }
    }
    @Published public var showClipboardInWheel: Bool { didSet { defaults.set(showClipboardInWheel, forKey: Key.showClipboardInWheel) } }
    /// Clipboard history is opt-in.
    @Published public var clipboardHistoryEnabled: Bool { didSet { defaults.set(clipboardHistoryEnabled, forKey: Key.clipboardHistoryEnabled) } }
    /// Keep history on disk between launches (off by default).
    @Published public var clipboardRemember: Bool { didSet { defaults.set(clipboardRemember, forKey: Key.clipboardRemember) } }
    @Published public var clipboardLimit: Int {
        didSet {
            let clamped = ClipboardHistory.limitRange.clamp(clipboardLimit)
            if clamped != clipboardLimit { clipboardLimit = clamped; return }
            defaults.set(clipboardLimit, forKey: Key.clipboardLimit)
        }
    }

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
        wheelHotKey = Self.loadCombo(defaults, key: Key.wheelHotKey, disabledKey: Key.wheelHotKeyDisabled, fallback: .defaultWheel)
        wheelSource = defaults.string(forKey: Key.wheelSource).flatMap(WheelSource.init(rawValue:)) ?? .favoritesThenFrequent
        wheelSlots = WheelLayout.slotRange.clamp(defaults.object(forKey: Key.wheelSlots) as? Int ?? WheelLayout.defaultSlots)
        showClipboardInWheel = defaults.object(forKey: Key.showClipboardInWheel) as? Bool ?? true
        clipboardHistoryEnabled = defaults.bool(forKey: Key.clipboardHistoryEnabled)
        clipboardRemember = defaults.bool(forKey: Key.clipboardRemember)
        clipboardLimit = ClipboardHistory.limitRange.clamp(defaults.object(forKey: Key.clipboardLimit) as? Int ?? ClipboardHistory.defaultLimit)
    }

    private static func loadCombo(_ defaults: UserDefaults, key: String, disabledKey: String, fallback: KeyCombo) -> KeyCombo? {
        if defaults.bool(forKey: disabledKey) { return nil }
        guard let data = defaults.data(forKey: key), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return fallback }
        if case .invalid = combo.validate() { return fallback }
        return combo
    }

    private func store(_ combo: KeyCombo?, key: String, disabledKey: String) {
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
            defaults.set(false, forKey: disabledKey)
        } else {
            defaults.removeObject(forKey: key)
            defaults.set(true, forKey: disabledKey)
        }
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
                            showFavoritesInMenu: showFavoritesInMenu, wheelHotKey: wheelHotKey, wheelSource: wheelSource,
                            wheelSlots: wheelSlots, showClipboardInWheel: showClipboardInWheel,
                            clipboardHistoryEnabled: clipboardHistoryEnabled, clipboardRemember: clipboardRemember,
                            clipboardLimit: clipboardLimit)
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
        wheelHotKey = clean.wheelHotKey
        wheelSource = clean.wheelSource
        wheelSlots = clean.wheelSlots
        showClipboardInWheel = clean.showClipboardInWheel
        clipboardHistoryEnabled = clean.clipboardHistoryEnabled
        clipboardRemember = clean.clipboardRemember
        clipboardLimit = clean.clipboardLimit
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
