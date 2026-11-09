import AppKit
import SwiftUI
import QuickDockCore

/// State of the Quick Wheel.
@MainActor
final class WheelViewModel: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var highlighted: Int?
    @Published var runningBundleIDs: Set<String> = []
    /// A short status shown in the hub ("Copied", errors).
    @Published var hubMessage: String?
    weak var controller: WheelController?

    var highlightedItem: LaunchItem? {
        guard let highlighted, items.indices.contains(highlighted) else { return nil }
        return items[highlighted]
    }

    func isRunning(_ item: LaunchItem) -> Bool {
        guard case .application(let app) = item.target, let id = app.bundleIdentifier else { return false }
        return runningBundleIDs.contains(id)
    }
}

/// A game-style radial menu: hold the wheel shortcut, flick towards an item, release to open it.
/// A quick tap instead leaves the wheel open for clicking; ⌥Tab repeatedly cycles like an app switcher.
///
/// The pointer position is read with `NSEvent.mouseLocation`, which needs no permissions.
@MainActor
final class WheelController: NSObject, NSWindowDelegate {
    static let wheelDiameter: CGFloat = 440
    static let clipboardWidth: CGFloat = 300
    static let gap: CGFloat = 18

    let model = WheelViewModel()
    private let env: AppEnvironment
    private let panel = LauncherPanel()
    private var trackTimer: Timer?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var center = NSPoint.zero
    private var shownAt = Date.distantPast
    private var isHolding = false
    /// Set when the keyboard picked a slot; pointer moves of more than a few points take over again.
    private var keyboardAnchor: NSPoint?
    private var clipboardOnLeft = false

    init(env: AppEnvironment) {
        self.env = env
        super.init()
        model.controller = self
        let root = WheelView(model: model, clipboardOnLeft: { [weak self] in self?.clipboardOnLeft ?? false })
            .environmentObject(env)
            .environmentObject(env.preferences)
            .environmentObject(env.icons)
            .environmentObject(env.clipboard)
        let hosting = NSHostingView(rootView: root)
        if #available(macOS 13.3, *) { hosting.sizingOptions = [] }
        panel.contentView = hosting
        panel.hasShadow = false // the glass surfaces draw their own depth
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        panel.setAccessibilityLabel("QuickDock Quick Wheel")
    }

    var isVisible: Bool { panel.isVisible }
    var panelReference: NSPanel { panel }

    // MARK: Hot key

    func hotKeyPressed() {
        if panel.isVisible {
            if isHolding {
                cycle(forward: true) // ⌥Tab again while holding ⌥: next slot
            } else {
                hide()
            }
            return
        }
        show(at: NSEvent.mouseLocation, holding: true)
    }

    func hotKeyReleased() {
        guard panel.isVisible, isHolding else { return }
        isHolding = false
        if model.highlighted != nil {
            openHighlighted()
        } else if Date().timeIntervalSince(shownAt) > 0.35 {
            hide() // held without choosing: cancel
        }
        // A quick tap leaves the wheel open for clicking.
    }

    // MARK: Showing

    func toggle() {
        panel.isVisible ? hide() : show(at: NSEvent.mouseLocation, holding: false)
    }

    func show(at point: NSPoint, holding: Bool) {
        env.launcherController?.hide()
        let prefs = env.preferences
        model.items = WheelLayout.items(from: env.library.items, source: prefs.wheelSource, slots: prefs.wheelSlots)
        model.runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        model.highlighted = nil
        model.hubMessage = nil
        isHolding = holding
        keyboardAnchor = nil
        shownAt = Date()

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let radius = Self.wheelDiameter / 2
        let showClipboard = prefs.showClipboardInWheel
        let clipboardSpace = showClipboard ? Self.clipboardWidth + Self.gap : 0

        // Keep the whole wheel on screen; prefer the clipboard on the right.
        center = NSPoint(x: min(max(point.x, visible.minX + radius), visible.maxX - radius),
                         y: min(max(point.y, visible.minY + radius), visible.maxY - radius))
        clipboardOnLeft = showClipboard && center.x + radius + clipboardSpace > visible.maxX
        if showClipboard && clipboardOnLeft && center.x - radius - clipboardSpace < visible.minX {
            center.x = visible.minX + radius + clipboardSpace // not enough room either side: shift
        }

        let width = Self.wheelDiameter + clipboardSpace
        let originX = clipboardOnLeft ? center.x - radius - clipboardSpace : center.x - radius
        panel.setFrame(NSRect(x: originX, y: center.y - radius, width: width, height: Self.wheelDiameter), display: false)
        model.objectWillChange.send()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.1; panel.animator().alphaValue = 1 }
        }
        startTracking()
        installMonitors()
    }

    func hide() {
        guard panel.isVisible else { return }
        stopTracking()
        removeMonitors()
        isHolding = false
        panel.orderOut(nil)
    }

    // MARK: Selection

    private func startTracking() {
        stopTracking()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackTimer = timer
    }

    private func stopTracking() {
        trackTimer?.invalidate()
        trackTimer = nil
    }

    private func trackPointer() {
        let mouse = NSEvent.mouseLocation
        if let anchor = keyboardAnchor {
            guard hypot(mouse.x - anchor.x, mouse.y - anchor.y) > 12 else { return }
            keyboardAnchor = nil
        }
        let dx = mouse.x - center.x, dy = mouse.y - center.y
        let distance = hypot(dx, dy)
        // While holding, any direction counts (flick). When clicking, only inside the wheel,
        // so moving to the clipboard panel doesn't change the highlight.
        if !isHolding && distance > Self.wheelDiameter / 2 { return }
        let slot = WheelLayout.slot(dx: dx, dy: dy, count: model.items.count, deadZone: 40)
        if slot != model.highlighted { model.highlighted = slot }
    }

    /// Updates the highlight for a pointer position (also used by the QA harness).
    func updateHighlight(forScreenPoint point: NSPoint) {
        let slot = WheelLayout.slot(dx: point.x - center.x, dy: point.y - center.y, count: model.items.count, deadZone: 40)
        model.highlighted = slot
    }

    var wheelCenter: NSPoint { center }

    func cycle(forward: Bool) {
        guard !model.items.isEmpty else { return }
        let count = model.items.count
        let current = model.highlighted ?? (forward ? -1 : 0)
        model.highlighted = (current + (forward ? 1 : -1) + count) % count
        keyboardAnchor = NSEvent.mouseLocation
    }

    // MARK: Actions

    func openHighlighted() {
        guard let index = model.highlighted else { return }
        open(index: index)
    }

    func open(index: Int) {
        guard model.items.indices.contains(index) else { return }
        let item = model.items[index]
        hide()
        Task {
            let outcome = await env.launcher.open(item)
            switch outcome {
            case .opened, .completed: break
            case .unavailable(let state):
                env.launcherController?.show()
                env.launcherController?.model.banner = .init(kind: .problem(item, state))
            case .failed(let message):
                env.launcherController?.show(message: message)
            }
        }
    }

    func copyClipboardEntry(_ entry: ClipboardEntry) {
        env.clipboard.copy(entry)
        model.hubMessage = "Copied — paste with ⌘V"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.hide() }
    }

    func openSettings() {
        hide()
        env.windows.showSettings(section: .wheel)
    }

    // MARK: Window and keyboard

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch UInt32(event.keyCode) {
        case KeyCodes.escape: hide(); return true
        case KeyCodes.returnKey, 0x4C: openHighlighted(); return true
        case KeyCodes.rightArrow, KeyCodes.downArrow: cycle(forward: true); return true
        case KeyCodes.leftArrow, KeyCodes.upArrow: cycle(forward: false); return true
        case KeyCodes.tab: cycle(forward: !event.modifierFlags.contains(.shift)); return true
        default: break
        }
        if let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
            open(index: digit - 1)
            return true
        }
        return false
    }
}
