import AppKit

// QuickDock is a menu-bar (agent) app: `LSUIElement` in Info.plist keeps it out of the Dock.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
