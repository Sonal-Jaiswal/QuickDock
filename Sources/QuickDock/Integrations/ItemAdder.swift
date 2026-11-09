import AppKit
import UniformTypeIdentifiers
import QuickDockCore

/// User-facing flows that add items or restore access to them via the open panel.
///
/// The open panel is how a sandboxed app receives access to files. Each URL it
/// returns is turned into a security-scoped bookmark immediately.
@MainActor
final class ItemAdder {
    struct Summary {
        var added: [LaunchItem] = []
        var duplicates: [LaunchItem] = []
        var failures: [String] = []

        var message: String {
            var parts: [String] = []
            if !added.isEmpty {
                parts.append(added.count == 1 ? "Added “\(added[0].name)”." : "Added \(added.count) items.")
            }
            if !duplicates.isEmpty {
                parts.append(duplicates.count == 1 ? "“\(duplicates[0].name)” is already in QuickDock."
                             : "\(duplicates.count) items were already in QuickDock.")
            }
            parts.append(contentsOf: failures)
            return parts.joined(separator: " ")
        }
    }

    private let library: LibraryManager
    private let factory: ItemFactory
    private let bookmarks: BookmarkProviding

    init(library: LibraryManager, factory: ItemFactory, bookmarks: BookmarkProviding = SecurityScopedBookmarks()) {
        self.library = library
        self.factory = factory
        self.bookmarks = bookmarks
    }

    // MARK: Adding

    @discardableResult
    func add(urls: [URL], categoryID: UUID? = nil) -> Summary {
        var summary = Summary()
        for url in urls {
            do {
                var item = try SecurityScope.access(url) { try factory.makeItem(for: url) }
                item.categoryID = categoryID
                switch library.add(item) {
                case .added(let added): summary.added.append(added)
                case .duplicate(let existing): summary.duplicates.append(existing)
                }
            } catch {
                summary.failures.append(error.localizedDescription)
            }
        }
        return summary
    }

    /// Shows an open panel for applications. Returns `nil` if cancelled.
    func chooseApplications(categoryID: UUID? = nil) -> Summary? {
        let panel = NSOpenPanel()
        panel.title = "Add Applications"
        panel.message = "Choose the apps you want in QuickDock."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return run(panel).map { add(urls: $0, categoryID: categoryID) }
    }

    /// Shows an open panel for files and folders. Returns `nil` if cancelled.
    func chooseFilesAndFolders(categoryID: UUID? = nil) -> Summary? {
        let panel = NSOpenPanel()
        panel.title = "Add Files and Folders"
        panel.message = "Choose files or folders. QuickDock will only have access to what you select."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        return run(panel).map { add(urls: $0, categoryID: categoryID) }
    }

    // MARK: Recovering

    /// Lets the user point QuickDock at the new location of a missing item (or grant
    /// access to an imported one). Returns an error message, or `nil` on success/cancel.
    func relocate(_ item: LaunchItem) -> String? {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        switch item.target {
        case .application(let app):
            panel.title = "Locate “\(item.name)”"
            panel.message = "Choose the application to use for “\(item.name)”."
            panel.allowedContentTypes = [.application]
            panel.canChooseDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            _ = app
        case .file(let ref):
            panel.title = "Locate “\(item.name)”"
            panel.message = "Choose “\(ref.lastPathComponent)” to give QuickDock access to it."
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.directoryURL = existingAncestor(of: ref.url)
            panel.nameFieldStringValue = ref.lastPathComponent
        case .folder(let ref):
            panel.title = "Locate “\(item.name)”"
            panel.message = "Choose the folder “\(ref.lastPathComponent)” to give QuickDock access to it."
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.directoryURL = existingAncestor(of: ref.url)
        case .website, .action:
            return nil
        }
        guard let url = run(panel)?.first else { return nil }

        do {
            let replacement = try SecurityScope.access(url) { try factory.makeItem(for: url) }
            guard replacement.kind == item.kind else {
                return "Choose a \(item.kind.displayName.lowercased()), not a \(replacement.kind.displayName.lowercased())."
            }
            library.updateTarget(item.id, to: replacement.target)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Re-grants access for every file and folder item inside a folder the user picks
    /// (useful after importing a configuration or moving to a new Mac).
    /// Returns the number of items whose access was restored, or `nil` if cancelled.
    func restoreAccess() -> Int? {
        let needing = library.items.filter { $0.target.fileReference != nil }
        let panel = NSOpenPanel()
        panel.title = "Restore File Access"
        panel.message = "Choose a folder that contains your QuickDock files (for example your Home folder). QuickDock will restore access to items inside it."
        panel.prompt = "Restore Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard let folder = run(panel)?.first else { return nil }

        let folderPath = PathUtilities.standardize(folder.path)
        var restored = 0
        SecurityScope.access(folder) {
            for item in needing {
                guard let ref = item.target.fileReference else { continue }
                let path = PathUtilities.standardize(ref.path)
                guard path == folderPath || path.hasPrefix(folderPath + "/"),
                      FileManager.default.fileExists(atPath: path),
                      let bookmark = try? bookmarks.makeBookmark(for: URL(fileURLWithPath: path)) else { continue }
                let newRef = FileReference(path: path, bookmark: bookmark)
                library.updateTarget(item.id, to: item.kind == .folder ? .folder(newRef) : .file(newRef))
                restored += 1
            }
        }
        return restored
    }

    // MARK: Helpers

    private func run(_ panel: NSOpenPanel) -> [URL]? {
        NSApp.activateQuickDock()
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }

    private func existingAncestor(of url: URL) -> URL {
        var candidate = url.deletingLastPathComponent()
        while candidate.path != "/" && !FileManager.default.fileExists(atPath: candidate.path) {
            candidate = candidate.deletingLastPathComponent()
        }
        return candidate
    }
}
