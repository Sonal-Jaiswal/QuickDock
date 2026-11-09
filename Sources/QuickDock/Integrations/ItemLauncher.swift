import AppKit
import QuickDockCore

/// Opens items with `NSWorkspace`. QuickDock never runs shell commands or scripts.
@MainActor
final class ItemLauncher {
    enum Outcome: Equatable {
        case opened
        /// Performed without opening anything (e.g. snippet copied); the message is shown briefly.
        case completed(String)
        case unavailable(ItemAvailability)
        case failed(String)

        var succeeded: Bool {
            switch self {
            case .opened, .completed: return true
            case .unavailable, .failed: return false
            }
        }
    }

    private let resolver: ItemResolver
    private let library: LibraryManager
    /// Opens QuickDock's own settings (for the built-in action).
    var showSettings: (() -> Void)?

    init(resolver: ItemResolver, library: LibraryManager) {
        self.resolver = resolver
        self.library = library
    }

    func open(_ item: LaunchItem) async -> Outcome {
        let resolution = resolver.resolve(item.target)
        if let updated = resolution.updatedTarget {
            library.updateTarget(item.id, to: updated)
        }
        guard resolution.availability.isAvailable else {
            return .unavailable(resolution.availability)
        }

        let outcome: Outcome
        switch item.target {
        case .application:
            outcome = await openApplication(at: resolution.url, name: item.name)
        case .file, .folder:
            outcome = await openDocument(resolution.url, name: item.name)
        case .website(let url):
            outcome = await openURL(url, failure: "The website couldn’t be opened. Check that a web browser is installed.")
        case .action(let action):
            outcome = await perform(action, appURL: resolution.url)
        }
        if outcome.succeeded {
            library.recordOpen(item.id)
        }
        return outcome
    }

    /// Shows the item in Finder.
    func reveal(_ item: LaunchItem) -> Bool {
        let resolution = resolver.resolve(item.target)
        if let updated = resolution.updatedTarget { library.updateTarget(item.id, to: updated) }
        guard let url = resolution.url, resolution.availability.isAvailable, url.isFileURL else { return false }
        SecurityScope.access(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return true
    }

    // MARK: Private

    private func openApplication(at url: URL?, name: String) async -> Outcome {
        guard let url else { return .unavailable(.applicationNotInstalled) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .opened
        } catch {
            return .failed("“\(name)” couldn’t be opened. \(error.localizedDescription)")
        }
    }

    private func openDocument(_ url: URL?, name: String) async -> Outcome {
        guard let url else { return .unavailable(.missing) }
        // Access must be active while Launch Services hands the file to the other app.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            try await NSWorkspace.shared.open(url, configuration: configuration)
            return .opened
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
                return .unavailable(.needsAccess)
            }
            return .failed("“\(name)” couldn’t be opened. \(error.localizedDescription)")
        }
    }

    private func openURL(_ url: URL, failure: String) async -> Outcome {
        do {
            try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return .opened
        } catch {
            return .failed(failure)
        }
    }

    private func perform(_ action: ActionReference, appURL: URL?) async -> Outcome {
        switch action.kind {
        case .copySnippet:
            guard let text = action.text, !text.isEmpty else { return .failed("This snippet is empty. Edit it to add text.") }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .completed("Copied to the clipboard")
        case .composeEmail:
            guard let url = PredefinedAction.mailtoURL(recipient: action.text) else {
                return .failed("The recipient address isn’t valid. Edit this action to fix it.")
            }
            return await openURL(url, failure: "No e-mail app is set up to handle new messages.")
        case .quickDockSettings:
            showSettings?()
            return .opened
        case .startScreenSaver, .takeScreenshot, .missionControl, .systemSettings:
            return await openApplication(at: appURL, name: action.kind.title)
        }
    }
}
