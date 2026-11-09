import Foundation

/// The portable configuration file written by "Export Configuration…".
///
/// Bookmarks are never exported: they are tied to this Mac and to QuickDock's
/// sandbox, so imported file and folder items ask the user to locate them once.
public struct ConfigurationDocument: Codable, Equatable {
    public static let formatIdentifier = "quickdock.configuration"
    public static let currentVersion = 1
    public static let fileExtension = "quickdock"

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var appVersion: String
    public var items: [ExportedItem]
    public var categories: [ItemCategory]
    public var preferences: PreferencesSnapshot?

    public struct ExportedItem: Codable, Equatable {
        public var item: LaunchItem
        /// PNG data for `.image` custom icons (base64 in JSON).
        public var customIconPNG: Data?
    }
}

/// The validated result of reading a configuration file.
public struct ImportPlan {
    public var items: [LaunchItem]
    public var categories: [ItemCategory]
    public var preferences: PreferencesSnapshot?
    /// Custom icon PNGs keyed by item ID; store them with `IconStore` before applying.
    public var iconImages: [UUID: Data]
    /// Human-readable notes about anything skipped or adjusted.
    public var warnings: [String]

    public var fileItemCount: Int {
        items.filter { $0.kind == .file || $0.kind == .folder }.count
    }
}

public enum ConfigurationTransfer {
    public static let maximumFileSize = 20 * 1024 * 1024
    public static let maximumItems = 5_000
    public static let maximumCategories = 200

    public enum TransferError: Error, Equatable, LocalizedError {
        case fileTooLarge
        case notAConfiguration
        case unsupportedVersion(Int)
        case tooManyItems

        public var errorDescription: String? {
            switch self {
            case .fileTooLarge: return "This file is too large to be a QuickDock configuration."
            case .notAConfiguration: return "This file isn’t a QuickDock configuration, or it is damaged."
            case .unsupportedVersion(let version):
                return "This configuration was made by a newer version of QuickDock (format \(version)). Update QuickDock and try again."
            case .tooManyItems: return "This configuration contains more items than QuickDock supports."
            }
        }
    }

    // MARK: Export

    public static func export(snapshot: LibrarySnapshot,
                              preferences: PreferencesSnapshot?,
                              iconStore: IconStore?,
                              appVersion: String,
                              date: Date = Date()) throws -> Data {
        let exportedItems = snapshot.items.map { item -> ConfigurationDocument.ExportedItem in
            var copy = item
            copy.target = strippingBookmarks(from: item.target)
            var png: Data?
            if case .image(let fileName) = item.customIcon {
                png = iconStore?.data(for: fileName)
                if png == nil { copy.customIcon = nil }
            }
            return .init(item: copy, customIconPNG: png)
        }
        let document = ConfigurationDocument(format: ConfigurationDocument.formatIdentifier,
                                             version: ConfigurationDocument.currentVersion,
                                             exportedAt: date, appVersion: appVersion,
                                             items: exportedItems, categories: snapshot.categories,
                                             preferences: preferences)
        return try LibraryStore.makeEncoder().encode(document)
    }

    public static func strippingBookmarks(from target: ItemTarget) -> ItemTarget {
        switch target {
        case .application(var app): app.bookmark = nil; return .application(app)
        case .file(var ref): ref.bookmark = nil; return .file(ref)
        case .folder(var ref): ref.bookmark = nil; return .folder(ref)
        case .website, .action: return target
        }
    }

    // MARK: Import

    /// Parses and validates a configuration file. Never trusts its contents:
    /// every item is re-validated and anything unsafe is dropped with a warning.
    public static func parse(_ data: Data) throws -> ImportPlan {
        guard data.count <= maximumFileSize else { throw TransferError.fileTooLarge }

        // Check the header first so a newer format gives a helpful message.
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? LibraryStore.makeDecoder().decode(Header.self, from: data),
              header.format == ConfigurationDocument.formatIdentifier, let version = header.version else {
            throw TransferError.notAConfiguration
        }
        guard (1...ConfigurationDocument.currentVersion).contains(version) else {
            throw TransferError.unsupportedVersion(version)
        }
        let document: ConfigurationDocument
        do {
            document = try LibraryStore.makeDecoder().decode(ConfigurationDocument.self, from: data)
        } catch {
            throw TransferError.notAConfiguration
        }
        guard document.items.count <= maximumItems else { throw TransferError.tooManyItems }

        var warnings: [String] = []

        // Categories
        var categories: [ItemCategory] = []
        var categoryIDs = Set<UUID>()
        for var category in document.categories.prefix(maximumCategories) {
            category.name = String(category.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(LibraryManager.maximumCategoryNameLength))
            guard !category.name.isEmpty else { continue }
            if !isSafeSymbolName(category.symbolName) { category.symbolName = "folder" }
            if categoryIDs.contains(category.id) { category.id = UUID() }
            categoryIDs.insert(category.id)
            categories.append(category)
        }
        if document.categories.count > maximumCategories {
            warnings.append("Only the first \(maximumCategories) categories were imported.")
        }

        // Items
        var items: [LaunchItem] = []
        var icons: [UUID: Data] = [:]
        var seenIDs = Set<UUID>()
        var skipped = 0
        for exported in document.items {
            guard var item = sanitize(exported.item) else {
                skipped += 1
                continue
            }
            if seenIDs.contains(item.id) { item.id = UUID() }
            seenIDs.insert(item.id)
            if let categoryID = item.categoryID, !categoryIDs.contains(categoryID) { item.categoryID = nil }
            if case .image = item.customIcon {
                item.customIcon = nil
                if let png = exported.customIconPNG, png.count <= IconStore.maximumImportedBytes,
                   IconStore.normalizedPNG(from: png) != nil {
                    icons[item.id] = png
                }
            }
            items.append(item)
        }
        if skipped > 0 {
            warnings.append("\(skipped) item\(skipped == 1 ? " was" : "s were") skipped because \(skipped == 1 ? "it was" : "they were") invalid or unsafe.")
        }

        return ImportPlan(items: items, categories: categories,
                          preferences: document.preferences?.sanitized(),
                          iconImages: icons, warnings: warnings)
    }

    /// Re-validates an imported item. Returns `nil` if it must be rejected.
    static func sanitize(_ item: LaunchItem) -> LaunchItem? {
        var item = item
        item.name = ItemFactory.clampName(item.name)
        item.openCount = max(0, item.openCount)
        item.target = strippingBookmarks(from: item.target) // never trust foreign bookmarks

        switch item.target {
        case .application(var app):
            app.path = PathUtilities.standardize(app.path)
            guard app.path.hasPrefix("/"), app.path.lowercased().hasSuffix(".app") else { return nil }
            if let bundleID = app.bundleIdentifier, bundleID.count > 255 || bundleID.contains("/") {
                app.bundleIdentifier = nil
            }
            item.target = .application(app)
            if item.name.isEmpty { item.name = ItemFactory.stripAppExtension((app.path as NSString).lastPathComponent) }
        case .file(var ref), .folder(var ref):
            ref.path = PathUtilities.standardize(ref.path)
            guard ref.path.hasPrefix("/"), ref.path.count < 4_096 else { return nil }
            item.target = item.kind == .file ? .file(ref) : .folder(ref)
            if item.name.isEmpty { item.name = ref.lastPathComponent }
        case .website(let url):
            guard let normalized = try? WebAddress.normalize(url.absoluteString) else { return nil }
            item.target = .website(normalized)
            if item.name.isEmpty { item.name = ItemFactory.defaultWebsiteName(for: normalized) }
        case .action(let action):
            guard let valid = try? ItemFactory.validatedAction(action.kind, text: action.text) else { return nil }
            item.target = .action(valid)
            if item.name.isEmpty { item.name = action.kind.title }
        }

        if case .symbol(let name, let tint) = item.customIcon, !isSafeSymbolName(name) {
            item.customIcon = .symbol(name: "star.fill", tint: tint)
        }
        return item
    }

    static func isSafeSymbolName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 100 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
    }
}
