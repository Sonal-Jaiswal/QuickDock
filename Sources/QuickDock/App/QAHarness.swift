#if DEBUG
import AppKit
import Carbon.HIToolbox
import QuickDockCore

/// Debug-only, in-process GUI checks. Never compiled into Release builds.
///
/// Run:  QUICKDOCK_QA=1 build/QuickDock.app/Contents/MacOS/QuickDock
/// It uses an isolated data folder and defaults suite, drives the real launcher,
/// settings and onboarding windows, then writes `report.json` and PNG captures to
/// `<sandbox tmp>/quickdock-qa/` and quits.
@MainActor
final class QAHarness {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["QUICKDOCK_QA"] == "1" }
    static var outputDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("quickdock-qa", isDirectory: true) }
    static var dataDirectory: URL { outputDirectory.appendingPathComponent("data", isDirectory: true) }
    static let defaultsSuite = "quickdock-qa"

    private let env: AppEnvironment
    private var results: [[String: String]] = []
    private let fixtures: URL

    init(env: AppEnvironment) {
        self.env = env
        fixtures = Self.outputDirectory.appendingPathComponent("fixtures", isDirectory: true)
    }

    static func prepareIsolatedStorage() {
        try? FileManager.default.removeItem(at: outputDirectory)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    func run() {
        Task { @MainActor in
            await self.steps()
            self.writeReport()
            NSApp.terminate(nil)
        }
    }

    // MARK: Steps

    private func steps() async {
        let phase = ProcessInfo.processInfo.environment["QUICKDOCK_QA_PHASE"] ?? "full"
        if phase == "persist-check" {
            await persistenceCheck()
            return
        }
        if phase == "external-add" {
            // Files are delivered via application(_:open:) by Launch Services; wait for them.
            await pause(3)
            let external = env.library.items.filter { !$0.detailText.contains("/Containers/") && $0.target.fileReference != nil }
            check("Files outside the sandbox were added via Open With", external.count >= 2, external.map(\.name).joined(separator: ", "))
            for item in external {
                check("Security-scoped bookmark created: \(item.name)", item.target.fileReference?.bookmark != nil, "")
            }
            env.library.flush()
            return
        }
        if phase == "screenshots" {
            await screenshots()
            return
        }
        if phase == "external-check" {
            await externalCheck()
            return
        }

        check("Single menu-bar status item exists", NSApp.windows.filter { $0.className.contains("NSStatusBarWindow") }.count == 1,
              "status bar windows: \(NSApp.windows.filter { $0.className.contains("NSStatusBarWindow") }.count)")
        check("Sandbox active", AppInfo.isSandboxed, ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "none")
        check("Displays detected", !NSScreen.screens.isEmpty, "\(NSScreen.screens.count) display(s)")

        // Hotkey
        let registered = env.hotKeys.register(.defaultLauncher)
        check("Register ⌥Space via Carbon", true, registered ? "registered" : "failed: \(env.hotKeys.status)")
        if registered {
            // A second registration of the same combination must be reported as a conflict.
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(KeyCodes.space, KeyCombo.defaultLauncher.modifiers.carbonFlags,
                                             EventHotKeyID(signature: 0x5445_5354, id: 9), GetApplicationEventTarget(), 0, &ref)
            check("Duplicate hotkey registration is rejected", status == eventHotKeyExistsErr, "status \(status)")
            if let ref { UnregisterEventHotKey(ref) }
        }
        let alt = KeyCombo(keyCode: KeyCodes.k, modifiers: [.control, .option, .command])
        check("Replace shortcut with ⌃⌥⌘K", env.hotKeys.tryReplacing(with: alt) == nil, "\(env.hotKeys.status)")
        check("Invalid shortcut ⌘Q refused and previous kept",
              env.hotKeys.tryReplacing(with: KeyCombo(keyCode: KeyCodes.q, modifiers: [.command])) != nil && env.hotKeys.currentCombo == alt,
              "\(env.hotKeys.status)")
        env.hotKeys.register(.defaultLauncher)

        // Items
        try? FileManager.default.createDirectory(at: fixtures.appendingPathComponent("Project Folder"), withIntermediateDirectories: true)
        let file = fixtures.appendingPathComponent("Quarterly Report.txt")
        try? Data("QuickDock QA".utf8).write(to: file)
        var urls = [file, fixtures.appendingPathComponent("Project Folder")]
        for id in ["com.apple.Safari", "com.apple.Notes", "com.apple.iCal", "com.apple.mail", "com.apple.TextEdit", "com.apple.Music", "com.apple.Terminal"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { urls.append(url) }
        }
        let summary = env.adder.add(urls: urls)
        check("Add apps, file and folder", summary.added.count == urls.count && summary.failures.isEmpty, summary.message)
        let again = env.adder.add(urls: [file])
        check("Duplicate item rejected", again.duplicates.count == 1, again.message)
        if let site = try? env.factory.makeWebsite(address: "developer.apple.com", name: "Apple Developer") { env.library.add(site) }
        if let snippet = try? env.factory.makeAction(.copySnippet, text: "Thanks — talk soon!", name: "Sign-off") { env.library.add(snippet) }
        if let mc = try? env.factory.makeAction(.missionControl) { env.library.add(mc) }
        let work = env.library.addCategory(name: "Work", symbolName: "briefcase")
        if let first = env.library.items.first(where: { $0.kind == .application }) {
            env.library.setPinned(first.id, true)
            env.library.setCategory(work?.id, for: [first.id])
        }
        check("Library contains 12 items", env.library.items.count == urls.count + 3, "\(env.library.items.count)")

        // Resolution
        let fileItem = env.library.items.first { $0.kind == .file }!
        let resolution = env.resolver.resolve(fileItem.target)
        check("Security-scoped bookmark created for file", fileItem.target.fileReference?.bookmark != nil, "")
        check("File resolves as available", resolution.availability == .available, "\(resolution.availability)")
        for item in env.library.items {
            let state = env.resolver.resolve(item.target).availability
            check("Resolve \(item.kind.rawValue) “\(item.name)”", state == .available, "\(state)")
        }

        // Launcher
        guard let controller = env.launcherController else { return }
        controller.show()
        await pause(0.8)
        let panel = controller.panelForTesting
        check("Launcher visible", panel.isVisible, "")
        check("Launcher is key without activating QuickDock", panel.isKeyWindow, "key=\(panel.isKeyWindow) active=\(NSApp.isActive)")
        let screen = panel.screen ?? NSScreen.main!
        check("Launcher centred horizontally on its display", abs(panel.frame.midX - screen.visibleFrame.midX) < 2,
              "panel \(panel.frame) screen \(screen.visibleFrame)")
        check("Launcher above normal windows", panel.level.rawValue > NSWindow.Level.normal.rawValue, "level \(panel.level.rawValue)")
        check("Launcher joins full-screen spaces", panel.collectionBehavior.contains(.fullScreenAuxiliary), "")
        capture(panel, "launcher-all")

        // Keyboard navigation
        let firstID = controller.model.selectedID
        postKey(KeyCodes.rightArrow)
        await pause(0.2)
        check("→ moves selection", controller.model.selectedID != firstID && controller.model.selectedID == controller.model.results[1].id, "")
        postKey(KeyCodes.downArrow)
        await pause(0.2)
        let expectedIndex = min(1 + env.preferences.gridColumns, controller.model.results.count - 1)
        check("↓ moves by one row", controller.model.selectedID == controller.model.results[expectedIndex].id, "")

        // Typing into search
        for (char, code) in [("s", KeyCodes.s), ("a", KeyCodes.a), ("f", KeyCodes.f)] { postKey(code, characters: char) }
        await pause(0.4)
        check("Typing filters results", controller.model.searchText == "saf" && controller.model.results.first?.name == "Safari",
              "text=\(controller.model.searchText) first=\(controller.model.results.first?.name ?? "-")")
        capture(panel, "launcher-search")
        postKey(KeyCodes.escape)
        await pause(0.2)
        check("Escape clears search first", controller.model.searchText.isEmpty && panel.isVisible, "")

        // Filters
        postKey(KeyCodes.tab)
        await pause(0.2)
        check("Tab switches to Favorites", controller.model.filter == .favorites && controller.model.results.count == 1, "\(controller.model.filter)")
        controller.model.filter = .applications
        await pause(0.3)
        check("Apps filter", controller.model.results.allSatisfy { $0.kind == .application }, "\(controller.model.results.count)")
        capture(panel, "launcher-apps")
        controller.model.filter = .websites
        await pause(0.2)
        check("Web filter", controller.model.results.map(\.name) == ["Apple Developer"], "")
        controller.model.filter = .all
        controller.model.categoryID = work?.id
        await pause(0.2)
        check("Category filter", controller.model.results.count == 1, "\(controller.model.results.count)")
        controller.model.categoryID = nil

        // Snippet action
        controller.model.searchText = "sign"
        await pause(0.2)
        postKey(KeyCodes.returnKey)
        await pause(0.5)
        check("Snippet action copies text", NSPasteboard.general.string(forType: .string) == "Thanks — talk soon!", "")
        controller.show()
        await pause(0.3)

        // Missing file
        try? FileManager.default.removeItem(at: file)
        controller.model.refreshAvailability()
        await pause(0.6)
        check("Deleted file reported missing", controller.model.availability(of: fileItem) == .missing,
              "\(controller.model.availability(of: fileItem))")
        controller.model.open(fileItem)
        await pause(0.4)
        if case .problem? = controller.model.banner?.kind {
            check("Missing file shows recovery banner", true, "")
        } else {
            check("Missing file shows recovery banner", false, "\(String(describing: controller.model.banner))")
        }
        capture(panel, "launcher-missing")
        controller.model.banner = nil

        // Uninstalled app
        let ghost = LaunchItem(name: "Retired App", target: .application(AppReference(bundleIdentifier: "com.example.not-installed",
                                                                                     path: "/Applications/Retired App.app")))
        env.library.add(ghost)
        check("Uninstalled app detected", env.resolver.resolve(ghost.target).availability == .applicationNotInstalled, "")
        env.library.remove(ghost.id)

        // Reorder (the same call the drag-and-drop delegate makes)
        controller.model.searchText = ""
        await pause(0.2)
        let before = env.library.items.map(\.id)
        controller.model.draggingID = before[3]
        controller.model.moveDragged(onto: env.library.items[0])
        controller.model.draggingID = nil
        check("Drag reorder updates library order", env.library.items.first?.id == before[3], "")

        // Restore file so screenshots look normal, and empty-state capture
        try? Data("QuickDock QA".utf8).write(to: file)
        controller.model.searchText = "zzzz"
        await pause(0.3)
        capture(panel, "launcher-no-results")
        controller.model.searchText = ""

        // Outside click / resign key → hides
        env.windows.showSettings()
        await pause(0.6)
        check("Launcher closes when another window takes focus", !panel.isVisible, "")

        // Settings sections
        for section in SettingsSection.allCases {
            env.windows.showSettings(section: section)
            await pause(0.5)
            if let window = NSApp.windows.first(where: { $0.title == "QuickDock Settings" }) {
                capture(window, "settings-\(section.rawValue)")
            }
        }
        check("Settings window opened", NSApp.windows.contains { $0.title == "QuickDock Settings" && $0.isVisible }, "")
        NSApp.windows.first { $0.title == "QuickDock Settings" }?.close()

        // Preferences persist
        env.preferences.gridColumns = 7
        env.preferences.appearance = .dark
        let reloaded = AppPreferences(defaults: UserDefaults(suiteName: Self.defaultsSuite)!)
        check("Preferences persist to defaults", reloaded.gridColumns == 7 && reloaded.appearance == .dark, "")
        await pause(0.4)
        controller.show()
        await pause(0.6)
        capture(panel, "launcher-dark")
        env.preferences.appearance = .light
        await pause(0.5)
        capture(panel, "launcher-light")
        env.preferences.appearance = .system
        env.preferences.gridColumns = AppPreferences.defaultColumns
        controller.hide()

        // Export / import round trip
        do {
            let data = try ConfigurationTransfer.export(snapshot: env.library.snapshot, preferences: env.preferences.snapshot,
                                                        iconStore: env.iconStore, appVersion: AppInfo.version)
            let plan = try ConfigurationTransfer.parse(data)
            check("Export/import round trip", plan.items.count == env.library.items.count, "\(plan.items.count) items")
        } catch {
            check("Export/import round trip", false, error.localizedDescription)
        }

        // Editor + onboarding
        env.windows.showNewItemEditor(kind: .website)
        await pause(0.6)
        if let window = NSApp.windows.first(where: { $0.title == "Add Website" }) { capture(window, "editor-website"); window.close() }
        if let item = env.library.items.first(where: { $0.kind == .action }) {
            env.windows.showEditor(for: item)
            await pause(0.6)
            if let window = NSApp.windows.first(where: { $0.title.hasPrefix("Edit") }) { capture(window, "editor-action"); window.close() }
        }
        env.windows.showOnboarding()
        await pause(0.8)
        if let window = NSApp.windows.first(where: { $0.title == "Welcome to QuickDock" }) { capture(window, "onboarding-welcome"); window.close() }

        env.library.flush()
        check("Library written to disk", FileManager.default.fileExists(atPath: env.library.store.fileURL.path), env.library.store.fileURL.path)
    }

    /// Phase 2, run in a fresh process: verifies data survived the restart and
    /// that security-scoped bookmarks still resolve.
    private func persistenceCheck() async {
        check("Items persisted across restart", env.library.items.count == 12, "\(env.library.items.count)")
        check("Favorite persisted", env.library.items.contains { $0.isPinned }, "")
        check("Category persisted", env.library.categories.map(\.name) == ["Work"], "")
        check("Order persisted (dragged item first)", env.library.items.first?.kind == .application, env.library.items.first?.name ?? "")
        for item in env.library.items where item.target.fileReference != nil {
            let resolution = env.resolver.resolve(item.target)
            check("Bookmark resolves after restart: \(item.name)", resolution.availability == .available, "\(resolution.availability)")
            if let url = resolution.url {
                let readable = SecurityScope.access(url) { FileManager.default.isReadableFile(atPath: url.path) }
                check("Scoped access works after restart: \(item.name)", readable, url.path)
            }
        }
        let prefs = env.preferences
        check("Preferences persisted across restart", prefs.gridColumns == AppPreferences.defaultColumns && prefs.appearance == .system, "")
    }

    /// Fresh process after `external-add`: proves access comes from the bookmark (a sibling
    /// file that was never chosen stays blocked by the sandbox) and survives the restart.
    private func externalCheck() async {
        let external = env.library.items.filter { !$0.detailText.contains("/Containers/") && $0.target.fileReference != nil }
        check("External items persisted", external.count >= 2, "\(external.count)")
        for item in external {
            let resolution = env.resolver.resolve(item.target)
            check("External bookmark resolves after restart: \(item.name)", resolution.availability == .available, "\(resolution.availability)")
            if let url = resolution.url {
                let readable = SecurityScope.access(url) { () -> Bool in
                    if item.kind == .folder { return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil }
                    return (try? Data(contentsOf: url)) != nil
                }
                check("Scoped read works after restart: \(item.name)", readable, url.path)
            }
        }
        if let sibling = ProcessInfo.processInfo.environment["QUICKDOCK_QA_UNGRANTED"] {
            let blocked = (try? Data(contentsOf: URL(fileURLWithPath: sibling))) == nil
            check("Sandbox blocks a file the user never chose", blocked, sibling)
        }
    }

    /// Captures real windows of the running app with a realistic library, for the website.
    private func screenshots() async {
        let ids = ["com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.Notes", "com.apple.reminders",
                   "com.apple.Music", "com.apple.Photos", "com.apple.Maps", "com.apple.TextEdit", "com.apple.Terminal",
                   "com.apple.Preview", "com.apple.ActivityMonitor"]
        let urls = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        env.adder.add(urls: urls)
        let work = env.library.addCategory(name: "Work", symbolName: "briefcase")
        for (address, name) in [("github.com", "GitHub"), ("developer.apple.com", "Apple Developer")] {
            if var site = try? env.factory.makeWebsite(address: address, name: name) {
                site.categoryID = work?.id
                env.library.add(site)
            }
        }
        if let snippet = try? env.factory.makeAction(.copySnippet, text: "Thanks — talk soon!", name: "Sign-off") { env.library.add(snippet) }
        if let mc = try? env.factory.makeAction(.missionControl) { env.library.add(mc) }
        if let shot = try? env.factory.makeAction(.takeScreenshot, name: "Screenshot") { env.library.add(shot) }
        for name in ["Safari", "Mail", "Notes", "GitHub"] {
            if let item = env.library.items.first(where: { $0.name == name }) { env.library.setPinned(item.id, true) }
        }
        guard let controller = env.launcherController else { return }
        let panel = controller.panelForTesting

        for (mode, label) in [(AppearanceMode.dark, "dark"), (.light, "light")] {
            env.preferences.appearance = mode
            controller.show()
            await pause(0.8)
            capture(panel, "shot-launcher-\(label)")
            controller.model.searchText = "no"
            await pause(0.5)
            capture(panel, "shot-search-\(label)")
            controller.model.searchText = ""
            controller.model.filter = .favorites
            await pause(0.5)
            capture(panel, "shot-favorites-\(label)")
            controller.model.filter = .all
            controller.hide()
            await pause(0.3)
        }
        env.preferences.appearance = .dark
        for section in [SettingsSection.general, .launcher, .shortcuts, .organization, .data, .about] {
            env.windows.showSettings(section: section)
            await pause(0.6)
            if let window = NSApp.windows.first(where: { $0.title == "QuickDock Settings" }) { capture(window, "shot-settings-\(section.rawValue)") }
        }
        NSApp.windows.first { $0.title == "QuickDock Settings" }?.close()
        env.windows.showNewItemEditor(kind: .website)
        await pause(0.6)
        if let window = NSApp.windows.first(where: { $0.title == "Add Website" }) { capture(window, "shot-editor"); window.close() }
        env.windows.showOnboarding()
        await pause(0.8)
        if let window = NSApp.windows.first(where: { $0.title == "Welcome to QuickDock" }) { capture(window, "shot-onboarding"); window.close() }
        env.preferences.appearance = .system
    }

    // MARK: Helpers

    private func check(_ name: String, _ passed: Bool, _ detail: String) {
        results.append(["name": name, "result": passed ? "PASS" : "FAIL", "detail": detail])
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func postKey(_ keyCode: UInt32, characters: String = "", modifiers: NSEvent.ModifierFlags = []) {
        guard let window = env.launcherController?.panelForTesting else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                            isARepeat: false, keyCode: UInt16(keyCode)) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private func capture(_ window: NSWindow, _ name: String) {
        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        if let image = WindowCapture.windowServerImage(of: window) {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            results.append(["name": "capture \(name)", "result": "INFO", "detail": "window server"])
        } else if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            results.append(["name": "capture \(name)", "result": "INFO", "detail": "view render (no backdrop)"])
        }
    }

    private func writeReport() {
        let passed = results.filter { $0["result"] == "PASS" }.count
        let failed = results.filter { $0["result"] == "FAIL" }.count
        let report: [String: Any] = ["passed": passed, "failed": failed, "results": results,
                                     "macOS": ProcessInfo.processInfo.operatingSystemVersionString]
        let name = (ProcessInfo.processInfo.environment["QUICKDOCK_QA_PHASE"] ?? "full") + "-report.json"
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.outputDirectory.appendingPathComponent(name))
        }
    }
}

/// Captures one of QuickDock's own windows through the window server, if the API is available.
enum WindowCapture {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func windowServerImage(of window: NSWindow) -> CGImage? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let function = unsafeBitCast(symbol, to: CreateImage.self)
        // kCGWindowListOptionIncludingWindow = 1 << 3; kCGWindowImageBoundsIgnoreFraming = 1 << 0, BestResolution = 1 << 3
        return function(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
    }
}

extension LauncherController {
    var panelForTesting: NSPanel { panelReference }
}
#endif
