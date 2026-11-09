import AppKit
import SwiftUI
import QuickDockCore

/// Creates and reuses QuickDock's standard windows (settings, onboarding, item editor).
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let env: AppEnvironment
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var editorWindow: NSWindow?
    private let settingsSelection = SettingsSelection()

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Settings

    func showSettings(section: SettingsSection? = nil) {
        if let section { settingsSelection.section = section }
        if settingsWindow == nil {
            let view = SettingsView(selection: settingsSelection)
                .environmentObject(env)
                .environmentObject(env.preferences)
                .environmentObject(env.library)
                .environmentObject(env.icons)
                .environmentObject(env.hotKeys)
                .environmentObject(env.loginItem)
                .environmentObject(env.clipboard)
            let window = makeWindow(title: "QuickDock Settings", size: NSSize(width: 760, height: 540),
                                    content: view, resizable: true)
            window.minSize = NSSize(width: 680, height: 460)
            window.setFrameAutosaveName("QuickDockSettings")
            settingsWindow = window
        }
        present(settingsWindow)
    }

    // MARK: Onboarding

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(finish: { [weak self] openLauncher in self?.finishOnboarding(openLauncher: openLauncher) })
                .environmentObject(env)
                .environmentObject(env.preferences)
                .environmentObject(env.library)
                .environmentObject(env.icons)
                .environmentObject(env.hotKeys)
            let window = makeWindow(title: "Welcome to QuickDock", size: NSSize(width: 680, height: 520),
                                    content: view, resizable: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            onboardingWindow = window
        }
        present(onboardingWindow)
    }

    private func finishOnboarding(openLauncher: Bool) {
        env.preferences.hasCompletedOnboarding = true
        onboardingWindow?.close()
        if openLauncher {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.env.launcherController?.show()
            }
        }
    }

    // MARK: Item editor

    func showEditor(for item: LaunchItem) {
        showEditor(mode: .edit(item))
    }

    func showNewItemEditor(kind: ItemEditorMode.NewKind) {
        showEditor(mode: .new(kind))
    }

    private func showEditor(mode: ItemEditorMode) {
        editorWindow?.close()
        let view = ItemEditorView(mode: mode, close: { [weak self] reopenLauncher in
            self?.editorWindow?.close()
            if reopenLauncher { self?.env.launcherController?.show() }
        })
        .environmentObject(env)
        .environmentObject(env.library)
        .environmentObject(env.icons)
        let title: String
        switch mode {
        case .edit(let item): title = "Edit “\(item.name)”"
        case .new(.website): title = "Add Website"
        case .new(.action): title = "Add Action"
        }
        let window = makeWindow(title: title, size: NSSize(width: 520, height: 600), content: view, resizable: false)
        editorWindow = window
        present(window)
    }

    // MARK: Helpers

    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content, resizable: Bool) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activateQuickDock()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            // Closing the welcome window counts as finishing it; QuickDock stays in the menu bar.
            env.preferences.hasCompletedOnboarding = true
            onboardingWindow = nil
        } else if window === editorWindow {
            editorWindow = nil
        }
    }
}
