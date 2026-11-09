import AppKit
import Combine
import QuickDockCore

/// The menu-bar icon. Click to toggle the launcher; right-click (or Control-click) for the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let env: AppEnvironment
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    init(env: AppEnvironment) {
        self.env = env
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = "QuickDockStatusItem"
        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("QuickDock")
        }
        menu.delegate = self
        env.hotKeys.$status
            .sink { [weak self] _ in self?.updateToolTip() }
            .store(in: &cancellables)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func updateToolTip() {
        if let display = env.hotKeyDisplay, env.hotKeys.isRegistered {
            statusItem.button?.toolTip = "QuickDock (\(display))"
        } else {
            statusItem.button?.toolTip = "QuickDock"
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            env.launcherController?.hide()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            env.launcherController?.toggle()
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open QuickDock", action: #selector(openLauncher), keyEquivalent: "")
        open.target = self
        if let combo = env.hotKeys.currentCombo, env.hotKeys.isRegistered {
            open.title = "Open QuickDock  (\(KeyboardLayout.displayString(for: combo)))"
        }
        menu.addItem(open)
        let wheelItem = NSMenuItem(title: "Open Quick Wheel", action: #selector(openWheel), keyEquivalent: "")
        wheelItem.target = self
        if let combo = env.wheelHotKeys.currentCombo, env.wheelHotKeys.isRegistered {
            wheelItem.title = "Open Quick Wheel  (\(KeyboardLayout.displayString(for: combo)))"
        }
        menu.addItem(wheelItem)

        let favorites = env.library.favorites
        if env.preferences.showFavoritesInMenu && !favorites.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for item in favorites.prefix(20) {
                let entry = NSMenuItem(title: item.name, action: #selector(openFavorite(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = item.id
                entry.image = menuIcon(for: item)
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        addItem("Add Applications…", #selector(addApplications))
        addItem("Add Files or Folders…", #selector(addFiles))
        addItem("Add Website…", #selector(addWebsite))
        menu.addItem(.separator())
        addItem("Settings…", #selector(openSettings), key: ",")
        addItem("About QuickDock", #selector(openAbout))
        menu.addItem(.separator())
        addItem("Quit QuickDock", #selector(quit), key: "q")
    }

    private func addItem(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func menuIcon(for item: LaunchItem) -> NSImage? {
        let image: NSImage?
        if let native = env.icons.image(for: item) {
            image = native.copy() as? NSImage
        } else {
            let symbol: String
            switch item.target {
            case .website: symbol = "globe"
            case .action(let action): symbol = action.kind.symbolName
            default: symbol = "app"
            }
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func openLauncher() { env.launcherController?.show() }
    @objc private func openWheel() {
        // Centre on the screen with the pointer, since the menu sits at the top edge.
        let screen = LauncherController.activeScreen().visibleFrame
        env.wheelController?.show(at: NSPoint(x: screen.midX, y: screen.midY), holding: false)
    }

    @objc private func openFavorite(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let item = env.library.item(withID: id) else { return }
        Task { @MainActor in
            let outcome = await env.launcher.open(item)
            switch outcome {
            case .opened, .completed: break
            case .unavailable(let state):
                showAlert(ItemProblemText.message(for: item, state: state))
            case .failed(let message):
                showAlert(message)
            }
        }
    }

    private func showAlert(_ message: String) {
        NSApp.activateQuickDock()
        let alert = NSAlert()
        alert.messageText = "Couldn’t open this item"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func addApplications() {
        if let summary = env.adder.chooseApplications() { env.launcherController?.show(message: summary.message) }
    }

    @objc private func addFiles() {
        if let summary = env.adder.chooseFilesAndFolders() { env.launcherController?.show(message: summary.message) }
    }

    @objc private func addWebsite() { env.windows.showNewItemEditor(kind: .website) }
    @objc private func openSettings() { env.windows.showSettings() }
    @objc private func openAbout() { env.windows.showSettings(section: .about) }
    @objc private func quit() { NSApp.terminate(nil) }

    /// A template image: a rounded dock with three tiles. Drawn in code so it is crisp at any scale.
    static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 3.2, yRadius: 3.2)
            outline.lineWidth = 1.4
            outline.stroke()
            for index in 0..<3 {
                let x = 4.0 + Double(index) * 3.75
                NSBezierPath(roundedRect: NSRect(x: x, y: 6.5, width: 2.5, height: 2.5), xRadius: 0.8, yRadius: 0.8).fill()
            }
            NSBezierPath(roundedRect: NSRect(x: 4, y: 10.6, width: 10, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "QuickDock"
        return image
    }
}
