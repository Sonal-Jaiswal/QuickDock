import Foundation

/// Creates launcher items from user input.
public struct ItemFactory: Sendable {
    public enum FactoryError: Error, Equatable, LocalizedError {
        case notFound(String)
        case emptyName
        case missingText(String)
        case invalidEmail

        public var errorDescription: String? {
            switch self {
            case .notFound(let path): return "“\((path as NSString).lastPathComponent)” couldn’t be found."
            case .emptyName: return "Enter a name."
            case .missingText(let label): return "\(label) can’t be empty."
            case .invalidEmail: return "Enter a valid e-mail address, or leave the recipient empty."
            }
        }
    }

    public static let maximumNameLength = 120

    public var bookmarks: BookmarkProviding

    public init(bookmarks: BookmarkProviding = SecurityScopedBookmarks()) {
        self.bookmarks = bookmarks
    }

    /// Creates an application, file or folder item for a URL the user chose.
    /// Call while QuickDock has access to `url` (open panel / drop), so the
    /// security-scoped bookmark can be created.
    public func makeItem(for url: URL) throws -> LaunchItem {
        let url = Self.userFacingURL(for: url.standardizedFileURL)
        guard FileManager.default.fileExists(atPath: url.path) else { throw FactoryError.notFound(url.path) }
        // Classify by what a symlink points to (e.g. /Applications/Safari.app → its cryptex),
        // but keep the path the user recognises.
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isApplicationKey, .localizedNameKey])

        let bookmark = try? bookmarks.makeBookmark(for: url)
        let isApplication = values?.isApplication ?? (resolved.pathExtension.lowercased() == "app")

        if isApplication {
            let bundle = Bundle(url: resolved)
            let displayName = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? Self.stripAppExtension(values?.localizedName ?? url.lastPathComponent)
            return LaunchItem(name: Self.clampName(displayName),
                              target: .application(AppReference(bundleIdentifier: bundle?.bundleIdentifier,
                                                                path: url.path, bookmark: bookmark)))
        }

        let name = Self.clampName(values?.localizedName ?? url.lastPathComponent)
        let reference = FileReference(path: url.path, bookmark: bookmark)
        let isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        return LaunchItem(name: name, target: isFolder ? .folder(reference) : .file(reference))
    }

    /// Creates a website item. Only http(s) addresses are accepted.
    public func makeWebsite(address: String, name: String? = nil) throws -> LaunchItem {
        let url = try WebAddress.normalize(address)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalName = trimmedName.isEmpty ? Self.defaultWebsiteName(for: url) : trimmedName
        return LaunchItem(name: Self.clampName(finalName), target: .website(url))
    }

    /// Creates a built-in action item.
    public func makeAction(_ kind: PredefinedAction, text: String? = nil, name: String? = nil) throws -> LaunchItem {
        let action = try Self.validatedAction(kind, text: text)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LaunchItem(name: Self.clampName(trimmedName.isEmpty ? kind.title : trimmedName), target: .action(action))
    }

    public static func validatedAction(_ kind: PredefinedAction, text: String?) throws -> ActionReference {
        var cleanText = text
        switch kind {
        case .copySnippet:
            guard let text, !text.isEmpty else { throw FactoryError.missingText(kind.textFieldLabel) }
            cleanText = String(text.prefix(PredefinedAction.maximumTextLength))
        case .composeEmail:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty || PredefinedAction.isPlausibleEmail(trimmed) else { throw FactoryError.invalidEmail }
            cleanText = trimmed.isEmpty ? nil : trimmed
        default:
            cleanText = nil
        }
        return ActionReference(kind: kind, text: cleanText)
    }

    /// "github.com" → "GitHub"-style friendly default: the host's main label, capitalized.
    public static func defaultWebsiteName(for url: URL) -> String {
        let host = WebAddress.displayName(for: url)
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return host }
        let main = labels[labels.count - 2]
        // Keep short or generic second-level labels readable, e.g. "co.uk" sites.
        if main.count <= 3, labels.count >= 3 { return String(labels[labels.count - 3]).capitalized }
        return main.prefix(1).uppercased() + main.dropFirst()
    }

    /// System apps updated through Rapid Security Responses (e.g. Safari) live in a cryptex
    /// and Launch Services may report that internal path. Prefer the familiar
    /// `/Applications/…` location when it points to the same app.
    public static func userFacingURL(for url: URL) -> URL {
        let marker = "/Cryptexes/App/System/Applications/"
        guard let range = url.path.range(of: marker) else { return url }
        let candidate = "/Applications/" + url.path[range.upperBound...]
        return FileManager.default.fileExists(atPath: candidate) ? URL(fileURLWithPath: candidate) : url
    }

    public static func stripAppExtension(_ name: String) -> String {
        name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    public static func clampName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumNameLength))
    }
}
