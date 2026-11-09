import Foundation

/// File-system queries used by `ItemResolver` (abstracted for tests).
public protocol FileSystemQuerying: Sendable {
    func fileExists(atPath path: String) -> Bool
    func isReadableFile(atPath path: String) -> Bool
}

public struct LocalFileSystem: FileSystemQuerying {
    public init() {}
    public func fileExists(atPath path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    public func isReadableFile(atPath path: String) -> Bool { FileManager.default.isReadableFile(atPath: path) }
}

/// Finds installed applications by bundle identifier (abstracted for tests).
public protocol ApplicationLocating: Sendable {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
}

/// Whether an item can currently be opened.
public enum ItemAvailability: Equatable, Sendable {
    case available
    /// The file or folder was moved or deleted (or its volume is not connected).
    case missing
    /// The application is no longer installed.
    case applicationNotInstalled
    /// The item exists but QuickDock needs the user to choose it again to grant access
    /// (for example after importing a configuration).
    case needsAccess

    public var isAvailable: Bool { self == .available }
}

public struct ItemResolution: Equatable, Sendable {
    /// The location to open, when available.
    public var url: URL?
    public var availability: ItemAvailability
    /// A refreshed target (new path, refreshed bookmark) the library should store.
    public var updatedTarget: ItemTarget?

    public init(url: URL?, availability: ItemAvailability, updatedTarget: ItemTarget? = nil) {
        self.url = url
        self.availability = availability
        self.updatedTarget = updatedTarget
    }
}

/// Works out where an item currently lives and whether it can be opened,
/// handling moved files, stale bookmarks and uninstalled applications.
public struct ItemResolver: Sendable {
    public var fileSystem: FileSystemQuerying
    public var applications: ApplicationLocating
    public var bookmarks: BookmarkProviding

    public init(fileSystem: FileSystemQuerying = LocalFileSystem(),
                applications: ApplicationLocating,
                bookmarks: BookmarkProviding = SecurityScopedBookmarks()) {
        self.fileSystem = fileSystem
        self.applications = applications
        self.bookmarks = bookmarks
    }

    public func resolve(_ target: ItemTarget) -> ItemResolution {
        switch target {
        case .application(let app):
            return resolveApplication(app)
        case .file(let ref):
            return resolveFile(ref, rebuild: ItemTarget.file)
        case .folder(let ref):
            return resolveFile(ref, rebuild: ItemTarget.folder)
        case .website(let url):
            return ItemResolution(url: url, availability: .available)
        case .action(let action):
            return resolveAction(action)
        }
    }

    // MARK: Applications

    private func resolveApplication(_ app: AppReference) -> ItemResolution {
        // 1. The exact copy the user chose.
        if !app.path.isEmpty, fileSystem.fileExists(atPath: app.path) {
            return ItemResolution(url: URL(fileURLWithPath: app.path), availability: .available)
        }
        // 2. Moved, renamed or reinstalled elsewhere: find it by bundle identifier.
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty,
           let found = applications.applicationURL(forBundleIdentifier: bundleID) {
            let url = ItemFactory.userFacingURL(for: found)
            var updated = app
            updated.path = url.path
            updated.bookmark = try? bookmarks.makeBookmark(for: url)
            return ItemResolution(url: url, availability: .available, updatedTarget: .application(updated))
        }
        // 3. A bookmark can follow an app that moved on the same volume.
        if let bookmark = app.bookmark, let resolved = try? bookmarks.resolveBookmark(bookmark),
           fileSystem.fileExists(atPath: resolved.url.path) {
            var updated = app
            updated.path = resolved.url.path
            if resolved.isStale { updated.bookmark = (try? bookmarks.makeBookmark(for: resolved.url)) ?? bookmark }
            return ItemResolution(url: resolved.url, availability: .available,
                                  updatedTarget: updated == app ? nil : .application(updated))
        }
        return ItemResolution(url: nil, availability: .applicationNotInstalled)
    }

    // MARK: Files and folders

    private func resolveFile(_ ref: FileReference, rebuild: (FileReference) -> ItemTarget) -> ItemResolution {
        if let bookmark = ref.bookmark {
            if let resolved = try? bookmarks.resolveBookmark(bookmark) {
                let url = resolved.url
                return SecurityScope.access(url) {
                    guard fileSystem.fileExists(atPath: url.path) else {
                        return ItemResolution(url: nil, availability: .missing)
                    }
                    var updated = ref
                    if resolved.isStale {
                        // Recreate while access is active so the new bookmark keeps the security scope.
                        updated.bookmark = (try? bookmarks.makeBookmark(for: url)) ?? bookmark
                    }
                    updated.path = url.path
                    return ItemResolution(url: url, availability: .available,
                                          updatedTarget: updated == ref ? nil : rebuild(updated))
                }
            }
            // The bookmark no longer resolves: the item was deleted, its volume is gone,
            // or access was revoked. Fall back to the last known path.
            if fileSystem.isReadableFile(atPath: ref.path) {
                var updated = ref
                updated.bookmark = try? bookmarks.makeBookmark(for: ref.url)
                return ItemResolution(url: ref.url, availability: .available, updatedTarget: rebuild(updated))
            }
            return ItemResolution(url: nil, availability: fileSystem.fileExists(atPath: ref.path) ? .needsAccess : .missing)
        }

        // No bookmark (e.g. imported from another Mac): usable only if readable.
        if fileSystem.isReadableFile(atPath: ref.path) {
            return ItemResolution(url: ref.url, availability: .available)
        }
        return ItemResolution(url: nil, availability: .needsAccess)
    }

    // MARK: Actions

    private func resolveAction(_ action: ActionReference) -> ItemResolution {
        guard let bundleID = action.kind.systemAppBundleIdentifier else {
            return ItemResolution(url: nil, availability: .available)
        }
        if let url = applications.applicationURL(forBundleIdentifier: bundleID) {
            return ItemResolution(url: url, availability: .available)
        }
        if let path = action.kind.systemAppFallbackPaths.first(where: fileSystem.fileExists(atPath:)) {
            return ItemResolution(url: URL(fileURLWithPath: path), availability: .available)
        }
        return ItemResolution(url: nil, availability: .applicationNotInstalled)
    }
}
