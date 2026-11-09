import Foundation

/// Creates and resolves bookmarks for user-selected files and folders.
public protocol BookmarkProviding: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark
}

public struct ResolvedBookmark: Equatable, Sendable {
    public var url: URL
    /// The bookmark still resolved, but should be recreated (e.g. the file moved).
    public var isStale: Bool
}

/// Security-scoped bookmarks, as required by the App Sandbox.
///
/// QuickDock only ever receives access to files the user explicitly chose
/// (open panel or drag and drop). A security-scoped bookmark lets it keep that
/// access across launches without asking for broader permissions such as Full Disk Access.
public struct SecurityScopedBookmarks: BookmarkProviding {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            // Without user-granted access (or outside the sandbox in unusual setups) fall back to a
            // regular bookmark, which still tracks moves and renames.
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    public func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &isStale)
            return ResolvedBookmark(url: url, isStale: isStale)
        } catch {
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &isStale)
            return ResolvedBookmark(url: url, isStale: isStale)
        }
    }
}

/// Balances `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`.
public enum SecurityScope {
    /// Runs `body` while access to `url` is active.
    @discardableResult
    public static func access<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
