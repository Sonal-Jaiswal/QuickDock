import AppKit
import SwiftUI
import QuickDockCore

/// Shows, positions and hides the launcher panel, and routes keyboard commands.
@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    let model: LauncherViewModel
    private let env: AppEnvironment
    private let panel = LauncherPanel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    /// Suppresses auto-hide while QuickDock deliberately moves focus (e.g. to an open panel).
    private var isTransitioning = false

    init(env: AppEnvironment) {
        self.env = env
        self.model = LauncherViewModel(env: env)
        super.init()

        let root = LauncherView(model: model)
            .environmentObject(env.preferences)
            .environmentObject(env.library)
            .environmentObject(env.icons)
            .environmentObject(env.hotKeys)
        let hosting = NSHostingView(rootView: root)
        if #available(macOS 13.3, *) { hosting.sizingOptions = [] }
        panel.contentView = LauncherBackground.makeContainer(hosting: hosting)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.handleEscape() }
        model.controller = self

        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    var isVisible: Bool { panel.isVisible }

    /// The underlying panel (used by the debug QA harness).
    var panelReference: NSPanel { panel }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(message: String? = nil) {
        model.prepareForPresentation()
        if let message, !message.isEmpty { model.showInfo(message) }
        let screen = Self.activeScreen()
        panel.setFrame(frame(on: screen), display: false)
        panel.invalidateShadow()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible && !reduceMotion {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
        }
        model.requestSearchFocus()
        installMonitors()
    }

    func hide() {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        model.didHide()
    }

    /// Hides the launcher while running `body` (open panels, editor windows), then
    /// optionally shows it again with a message.
    func perform(reopenAfter: Bool, _ body: () -> String?) {
        isTransitioning = true
        hide()
        let message = body()
        isTransitioning = false
        if reopenAfter { show(message: message) }
    }

    /// Re-fits the panel when preferences that affect its size change.
    func refreshLayout() {
        guard panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        panel.setFrame(frame(on: screen), display: true, animate: false)
        panel.invalidateShadow()
    }

    // MARK: Geometry

    /// The display the user is working on: the one containing the mouse pointer.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let metrics = LauncherMetrics(preferences: env.preferences)
        var size = metrics.panelSize
        // Never exceed the screen; the grid scrolls if needed.
        size.width = min(size.width, visible.width - 40)
        size.height = min(size.height, visible.height - 40)
        let x = visible.midX - size.width / 2
        // Slightly above centre, where the eye naturally lands.
        let y = visible.minY + (visible.height - size.height) * 0.6
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    @objc private func screenParametersChanged() {
        guard panel.isVisible else { return }
        panel.setFrame(frame(on: panel.screen ?? Self.activeScreen()), display: true)
    }

    // MARK: Window delegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking outside (another app, the desktop) closes the launcher.
        guard !isTransitioning, !model.isShowingContextMenu else { return }
        hide()
    }

    // MARK: Keyboard

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        // Backup for outside clicks that don't change the key window (e.g. on the desktop).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isTransitioning, !self.model.isShowingContextMenu else { return }
                self.hide()
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleEscape() {
        if model.banner != nil {
            model.banner = nil
        } else if !model.searchText.isEmpty {
            model.searchText = ""
        } else {
            hide()
        }
    }

    /// Returns true when the event was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let keyCode = UInt32(event.keyCode)

        switch keyCode {
        case KeyCodes.escape:
            handleEscape()
            return true
        case KeyCodes.leftArrow:
            model.moveSelection(by: -1); return true
        case KeyCodes.rightArrow:
            model.moveSelection(by: 1); return true
        case KeyCodes.upArrow:
            model.moveSelection(by: -model.columns); return true
        case KeyCodes.downArrow:
            model.moveSelection(by: model.columns); return true
        case KeyCodes.returnKey, 0x4C /* keypad enter */:
            command ? model.revealSelected() : model.openSelected()
            return true
        case KeyCodes.tab:
            model.cycleFilter(forward: !flags.contains(.shift))
            return true
        default:
            break
        }

        guard command else { return false }
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let digit = Int(characters), (1...9).contains(digit) {
            model.openItem(atVisibleIndex: digit - 1)
            return true
        }
        switch characters {
        case "e": model.editSelected(); return true
        case "d": model.toggleFavoriteSelected(); return true
        case ",": perform(reopenAfter: false) { env.windows.showSettings(); return nil }; return true
        case "w": hide(); return true
        case "f": model.requestSearchFocus(); return true
        // Standard editing commands for the search field (QuickDock isn't the active app,
        // so route them explicitly).
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        case "z":
            let selector = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            return NSApp.sendAction(selector, to: nil, from: nil)
        default: return false
        }
    }
}

/// Sizes derived from the user's grid preferences.
struct LauncherMetrics {
    let columns: Int
    let rows: Int
    let iconSize: CGFloat
    let showLabels: Bool

    @MainActor
    init(preferences: AppPreferences) {
        columns = preferences.gridColumns
        rows = preferences.maxVisibleRows
        iconSize = CGFloat(preferences.iconSize.points)
        showLabels = preferences.showLabels
    }

    static let horizontalPadding: CGFloat = 14
    static let gridSpacing: CGFloat = 4
    static let headerHeight: CGFloat = 60 + 40 // search + filters
    static let footerHeight: CGFloat = 36

    var cellWidth: CGFloat { iconSize + (showLabels ? 40 : 22) }
    var cellHeight: CGFloat { iconSize + (showLabels ? 48 : 20) }

    var gridHeight: CGFloat { CGFloat(rows) * cellHeight + CGFloat(rows - 1) * 6 + 20 }

    var panelSize: NSSize {
        let width = CGFloat(columns) * cellWidth + CGFloat(columns - 1) * Self.gridSpacing + Self.horizontalPadding * 2
        let height = Self.headerHeight + gridHeight + Self.footerHeight
        return NSSize(width: max(width, 560), height: height)
    }
}
