import AppKit
import QuickDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showLauncherNotification = Notification.Name("io.github.quickdock.showLauncher")

    private var env: AppEnvironment!
    /// Files opened before launch finished (e.g. dropped on the app icon to start it).
    private var pendingOpenURLs: [URL] = []
    private var statusItem: StatusItemController?
    private var launcher: LauncherController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one QuickDock may run, otherwise there would be two menu-bar icons and a
        // shortcut conflict. A second copy asks the first to show its launcher and quits.
        if Self.anotherInstanceIsRunning() {
            DistributedNotificationCenter.default().postNotificationName(Self.showLauncherNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        NSApp.mainMenu = MainMenu.make()
        #if DEBUG
        if QAHarness.isEnabled {
            let phase = ProcessInfo.processInfo.environment["QUICKDOCK_QA_PHASE"] ?? "full"
            if phase == "full" || phase == "external-add" || phase == "screenshots" {
                QAHarness.prepareIsolatedStorage()
            }
            let defaults = UserDefaults(suiteName: QAHarness.defaultsSuite)!
            defaults.set(true, forKey: "hasCompletedOnboarding")
            env = AppEnvironment(dataDirectory: QAHarness.dataDirectory, defaults: defaults)
        } else {
            env = AppEnvironment()
        }
        #else
        env = AppEnvironment()
        #endif
        env.windows = WindowCoordinator(env: env)

        let launcher = LauncherController(env: env)
        self.launcher = launcher
        env.launcherController = launcher
        env.launcher.showSettings = { [weak self] in self?.env.windows.showSettings() }
        env.hotKeys.onPressed = { [weak launcher] in launcher?.toggle() }

        statusItem = StatusItemController(env: env)

        let isFirstLaunch = !env.preferences.hasCompletedOnboarding
        env.registerHotKey(isFirstLaunch: isFirstLaunch)
        observePreferenceChanges()

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showLauncherRequested),
                                                            name: Self.showLauncherNotification, object: nil)

        if isFirstLaunch {
            env.windows.showOnboarding()
        }
        processPendingOpenURLs()
        #if DEBUG
        if QAHarness.isEnabled {
            QAHarness(env: env).run()
            return
        }
        #endif
        if let notice = env.loadNotice {
            NSApp.activateQuickDock()
            let alert = NSAlert()
            alert.messageText = "QuickDock restored your items"
            alert.informativeText = notice
            alert.runModal()
        }
    }

    /// Files, folders or apps dropped onto QuickDock's icon (or opened with it) are added as items.
    /// macOS grants the sandbox access needed to bookmark them.
    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        guard let env, let launcher else {
            pendingOpenURLs.append(contentsOf: fileURLs)
            return
        }
        let summary = env.adder.add(urls: fileURLs)
        #if DEBUG
        if QAHarness.isEnabled { return }
        #endif
        launcher.show(message: summary.message)
    }

    private func processPendingOpenURLs() {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        application(NSApp, open: urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        env?.library.flush()
        env?.hotKeys.tearDown()
        statusItem?.remove()
    }

    /// Reopening QuickDock from Finder or Spotlight while it runs shows the launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func showLauncherRequested() {
        launcher?.show()
    }

    private func observePreferenceChanges() {
        let prefs = env.preferences
        // Grid changes resize an open launcher immediately.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.launcher?.refreshLayout() }
        }
        _ = prefs
    }

    private static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != current.processIdentifier && !$0.isTerminated }
    }
}

/// A minimal main menu. QuickDock has no Dock icon, but the menu provides standard
/// key equivalents (copy, paste, close…) for its windows.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "QuickDock")
        appMenu.addItem(withTitle: "About QuickDock", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide QuickDock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit QuickDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }
}
