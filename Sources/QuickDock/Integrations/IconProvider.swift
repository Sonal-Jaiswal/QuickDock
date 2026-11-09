import AppKit
import UniformTypeIdentifiers
import QuickDockCore

/// Supplies native icons for applications, files and folders, with caching.
///
/// Websites, actions and symbol icons are drawn by `ItemIconView` instead,
/// so QuickDock never needs network access to fetch favicons.
@MainActor
final class IconProvider: ObservableObject {
    private let cache = NSCache<NSString, NSImage>()
    private let iconStore: IconStore
    private let bookmarks: BookmarkProviding

    init(iconStore: IconStore, bookmarks: BookmarkProviding = SecurityScopedBookmarks()) {
        self.iconStore = iconStore
        self.bookmarks = bookmarks
        cache.countLimit = 500
    }

    /// The native (or custom image) icon, or `nil` when the item is drawn as a tile.
    func image(for item: LaunchItem) -> NSImage? {
        let key = cacheKey(for: item) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = loadImage(for: item) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate() { cache.removeAllObjects() }

    private func cacheKey(for item: LaunchItem) -> String {
        var key = item.id.uuidString
        switch item.target {
        case .application(let app): key += "|" + app.path
        case .file(let ref), .folder(let ref): key += "|" + ref.path
        default: break
        }
        if case .image(let name) = item.customIcon { key += "|img:" + name }
        return key
    }

    private func loadImage(for item: LaunchItem) -> NSImage? {
        if case .image(let fileName) = item.customIcon {
            if let url = iconStore.url(for: fileName), let image = NSImage(contentsOf: url) { return image }
        }
        if case .symbol = item.customIcon { return nil }

        switch item.target {
        case .application(let app):
            if FileManager.default.fileExists(atPath: app.path) {
                return NSWorkspace.shared.icon(forFile: app.path)
            }
            if let bundleID = app.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSWorkspace.shared.icon(for: .application)
        case .file(let ref):
            return fileIcon(ref) ?? NSWorkspace.shared.icon(for: UTType(filenameExtension: ref.url.pathExtension) ?? .data)
        case .folder(let ref):
            return fileIcon(ref) ?? NSWorkspace.shared.icon(for: .folder)
        case .website, .action:
            return nil
        }
    }

    /// The real Finder icon (including custom folder icons and document previews), read
    /// while security-scoped access is active.
    private func fileIcon(_ ref: FileReference) -> NSImage? {
        var url = ref.url
        if let bookmark = ref.bookmark, let resolved = try? bookmarks.resolveBookmark(bookmark) {
            url = resolved.url
        }
        return SecurityScope.access(url) {
            FileManager.default.fileExists(atPath: url.path) ? NSWorkspace.shared.icon(forFile: url.path) : nil
        }
    }
}
