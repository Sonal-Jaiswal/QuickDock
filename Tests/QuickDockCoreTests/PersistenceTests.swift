import Foundation
import Testing
@testable import QuickDockCore

@Suite("Library store")
struct LibraryStoreTests {
    @Test("Missing file loads as empty")
    func emptyOnFirstLaunch() {
        let dir = TemporaryDirectory()
        #expect(LibraryStore(directory: dir.url.appendingPathComponent("new")).load() == .empty)
    }

    @Test("Save then load returns the same data")
    func roundTrip() throws {
        let dir = TemporaryDirectory()
        let store = LibraryStore(directory: dir.url)
        let snapshot = LibrarySnapshot(items: [.website("example.com"), .app("Notes", bundleID: "com.apple.Notes")],
                                       categories: [ItemCategory(name: "Work", symbolName: "briefcase")])
        try store.save(snapshot)
        #expect(store.load() == .loaded(snapshot))
    }

    @Test("A previous good version is kept as a backup")
    func backup() throws {
        let dir = TemporaryDirectory()
        let store = LibraryStore(directory: dir.url)
        let first = LibrarySnapshot(items: [.website("one.com")])
        let second = LibrarySnapshot(items: [.website("one.com"), .website("two.com")])
        try store.save(first)
        try store.save(second)
        let backup = try LibraryStore.makeDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: store.backupURL))
        #expect(backup == first)
    }

    @Test("A corrupted file is preserved and the backup is used")
    func corruptionRecovery() throws {
        let dir = TemporaryDirectory()
        let store = LibraryStore(directory: dir.url)
        let good = LibrarySnapshot(items: [.website("good.com")])
        try store.save(good)
        try store.save(LibrarySnapshot(items: [.website("good.com"), .website("newer.com")]))
        try Data("{ this is not json".utf8).write(to: store.fileURL)

        guard case .recovered(let snapshot, let preserved, let fromBackup) = store.load() else {
            Issue.record("Expected recovery")
            return
        }
        #expect(fromBackup)
        #expect(snapshot == good)
        #expect(FileManager.default.fileExists(atPath: preserved.path))
        #expect(preserved.lastPathComponent.hasPrefix("library.unreadable-"))
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "{ this is not json")
    }

    @Test("A library from a newer QuickDock is never overwritten")
    func futureSchema() throws {
        let dir = TemporaryDirectory()
        let store = LibraryStore(directory: dir.url)
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let future = #"{"schemaVersion": 99, "items": [], "categories": []}"#
        try Data(future.utf8).write(to: store.fileURL)
        guard case .recovered(_, let preserved, _) = store.load() else {
            Issue.record("Expected the future file to be set aside")
            return
        }
        #expect(try String(contentsOf: preserved, encoding: .utf8) == future)
    }

    @Test("Interrupted first write falls back to the backup")
    func onlyBackupExists() throws {
        let dir = TemporaryDirectory()
        let store = LibraryStore(directory: dir.url)
        let snapshot = LibrarySnapshot(items: [.website("a.com")])
        try LibraryStore.makeEncoder().encode(snapshot).write(to: store.backupURL)
        #expect(store.load() == .loaded(snapshot))
    }
}

@Suite("Preferences")
@MainActor
struct PreferencesTests {
    func makeDefaults() -> UserDefaults {
        let name = "QuickDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Defaults on first launch")
    func firstLaunch() {
        let prefs = AppPreferences(defaults: makeDefaults())
        #expect(prefs.appearance == .system)
        #expect(prefs.hotKey == .defaultLauncher)
        #expect(prefs.gridColumns == AppPreferences.defaultColumns)
        #expect(prefs.showLabels)
        #expect(!prefs.hasCompletedOnboarding)
    }

    @Test("Values persist across instances")
    func persistence() {
        let defaults = makeDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.appearance = .dark
        prefs.hotKey = KeyCombo(keyCode: KeyCodes.k, modifiers: [.control, .option])
        prefs.gridColumns = 8
        prefs.iconSize = .large
        prefs.showLabels = false
        prefs.startFilter = .lastUsed
        prefs.lastFilter = .websites
        prefs.hasCompletedOnboarding = true

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.hotKey == KeyCombo(keyCode: KeyCodes.k, modifiers: [.control, .option]))
        #expect(reloaded.gridColumns == 8)
        #expect(reloaded.iconSize == .large)
        #expect(!reloaded.showLabels)
        #expect(reloaded.initialFilter == .websites)
        #expect(reloaded.hasCompletedOnboarding)
    }

    @Test("Disabling the shortcut persists")
    func disabledHotKey() {
        let defaults = makeDefaults()
        AppPreferences(defaults: defaults).hotKey = nil
        #expect(AppPreferences(defaults: defaults).hotKey == nil)
    }

    @Test("Out-of-range values are clamped")
    func clamping() {
        let defaults = makeDefaults()
        defaults.set(50, forKey: "gridColumns")
        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.gridColumns == AppPreferences.columnRange.upperBound)
        prefs.maxVisibleRows = -3
        #expect(prefs.maxVisibleRows == AppPreferences.rowRange.lowerBound)
    }

    @Test("Reset restores defaults but keeps onboarding state")
    func reset() {
        let prefs = AppPreferences(defaults: makeDefaults())
        prefs.appearance = .light
        prefs.gridColumns = 9
        prefs.hasCompletedOnboarding = true
        prefs.resetToDefaults()
        #expect(prefs.appearance == .system)
        #expect(prefs.gridColumns == AppPreferences.defaultColumns)
        #expect(prefs.hasCompletedOnboarding)
    }
}

@Suite("Icon store")
struct IconStoreTests {
    /// A 2×2 red PNG.
    static let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAwMDAxAADAB0EAf9Ls9kXAAAAAElFTkSuQmCC")!

    @Test("Stores, reads and cleans up icons")
    func lifecycle() throws {
        let dir = TemporaryDirectory()
        let store = IconStore(directory: dir.url.appendingPathComponent("Icons"))
        let name = try store.storeImageData(Self.tinyPNG)
        #expect(IconStore.isValidFileName(name))
        #expect(store.data(for: name) != nil)
        store.removeUnused(keeping: [])
        #expect(store.data(for: name) == nil)
    }

    @Test("Rejects non-images")
    func rejectsGarbage() {
        let dir = TemporaryDirectory()
        let store = IconStore(directory: dir.url)
        #expect(throws: IconStore.IconError.self) { try store.storeImageData(Data("not an image".utf8)) }
    }

    @Test("Rejects path traversal in file names", arguments: ["../../etc/passwd", "a.png", "/tmp/x.png", "\(UUID().uuidString).jpg"])
    func traversal(name: String) {
        #expect(!IconStore.isValidFileName(name))
        #expect(IconStore(directory: URL(fileURLWithPath: "/tmp")).url(for: name) == nil)
    }
}
