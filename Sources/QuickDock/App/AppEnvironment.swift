import AppKit
import Combine
import QuickDockCore

/// Owns QuickDock's long-lived services and wires them together.
@MainActor
final class AppEnvironment: ObservableObject {
    let preferences: AppPreferences
    let library: LibraryManager
    let iconStore: IconStore
    let factory: ItemFactory
    let resolver: ItemResolver
    let launcher: ItemLauncher
    let icons: IconProvider
    let adder: ItemAdder
    let hotKeys: HotKeyCenter
    /// The Quick Wheel's own shortcut (separate Carbon registration).
    let wheelHotKeys: HotKeyCenter
    let clipboard: ClipboardMonitor
    let loginItem: LaunchAtLoginController

    /// Set by `AppDelegate` once UI controllers exist.
    weak var launcherController: LauncherController?
    weak var wheelController: WheelController?
    var windows: WindowCoordinator!

    /// A problem found while loading the library (shown once after launch).
    var loadNotice: String?

    private var cancellables = Set<AnyCancellable>()

    init(dataDirectory: URL = LibraryStore.defaultDirectory(), defaults: UserDefaults = .standard,
         pasteboard: NSPasteboard = .general) {
        preferences = AppPreferences(defaults: defaults)
        iconStore = IconStore(directory: dataDirectory.appendingPathComponent("Icons", isDirectory: true))
        library = LibraryManager(store: LibraryStore(directory: dataDirectory), iconStore: iconStore)
        factory = ItemFactory()
        resolver = ItemResolver(applications: WorkspaceApplications())
        launcher = ItemLauncher(resolver: resolver, library: library)
        icons = IconProvider(iconStore: iconStore)
        adder = ItemAdder(library: library, factory: factory)
        hotKeys = HotKeyCenter(signature: 0x5144_4B31) // "QDK1"
        wheelHotKeys = HotKeyCenter(signature: 0x5144_4B32) // "QDK2"
        clipboard = ClipboardMonitor(preferences: preferences, store: ClipboardStore(directory: dataDirectory), pasteboard: pasteboard)
        loginItem = LaunchAtLoginController()

        switch library.load() {
        case .recovered(_, let preserved, let fromBackup):
            loadNotice = fromBackup
                ? "QuickDock’s item list was damaged, so your most recent backup was restored. The damaged file was kept at \(preserved.path)."
                : "QuickDock’s item list couldn’t be read and no backup was available. The unreadable file was kept at \(preserved.path)."
        case .empty, .loaded:
            break
        }
        library.cleanUpUnusedIcons()

        // Appearance follows the preference immediately.
        preferences.$appearance
            .sink { mode in
                switch mode {
                case .system: NSApp.appearance = nil
                case .light: NSApp.appearance = NSAppearance(named: .aqua)
                case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
            .store(in: &cancellables)

        library.$items
            .dropFirst()
            .sink { [weak self] _ in self?.icons.invalidate() }
            .store(in: &cancellables)
    }

    /// The shortcut as the user sees it, e.g. "⌥Space".
    var hotKeyDisplay: String? {
        hotKeys.currentCombo.map(KeyboardLayout.displayString(for:))
    }

    /// Registers the Quick Wheel shortcut, falling back on first launch if ⌥Tab is taken.
    func registerWheelHotKey(isFirstLaunch: Bool) {
        guard let combo = preferences.wheelHotKey else {
            wheelHotKeys.register(nil)
            return
        }
        if wheelHotKeys.register(combo) { return }
        if isFirstLaunch && combo == .defaultWheel {
            let fallback = KeyCombo(keyCode: KeyCodes.tab, modifiers: [.control, .option])
            if fallback != preferences.hotKey && wheelHotKeys.register(fallback) { preferences.wheelHotKey = fallback }
        }
    }

    /// Registers the preferred shortcut. On first launch, if Option-Space is taken,
    /// falls back to Control-Option-Space and records that choice.
    func registerHotKey(isFirstLaunch: Bool) {
        guard let combo = preferences.hotKey else {
            hotKeys.register(nil)
            return
        }
        if hotKeys.register(combo) { return }
        if isFirstLaunch && combo == .defaultLauncher {
            for fallback in [KeyCombo.fallbackLauncher, KeyCombo(keyCode: KeyCodes.space, modifiers: [.command, .shift])]
            where hotKeys.register(fallback) {
                preferences.hotKey = fallback
                return
            }
        }
    }
}
