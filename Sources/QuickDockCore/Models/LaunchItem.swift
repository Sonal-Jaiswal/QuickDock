import Foundation

/// The broad type of a launcher item. Used for filtering and display.
public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case application
    case file
    case folder
    case website
    case action

    public var displayName: String {
        switch self {
        case .application: return "Application"
        case .file: return "File"
        case .folder: return "Folder"
        case .website: return "Website"
        case .action: return "Action"
        }
    }
}

/// A single entry in the user's QuickDock library.
public struct LaunchItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    /// The user-visible name. Users may rename items freely.
    public var name: String
    /// What the item opens.
    public var target: ItemTarget
    /// Optional user-defined category.
    public var categoryID: UUID?
    /// Favorites appear in the Favorites filter and in the menu-bar menu.
    public var isPinned: Bool
    /// Overrides the native icon when set.
    public var customIcon: CustomIcon?
    public var createdAt: Date
    public var lastOpenedAt: Date?
    public var openCount: Int

    public var kind: ItemKind { target.kind }

    public init(
        id: UUID = UUID(),
        name: String,
        target: ItemTarget,
        categoryID: UUID? = nil,
        isPinned: Bool = false,
        customIcon: CustomIcon? = nil,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        openCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.categoryID = categoryID
        self.isPinned = isPinned
        self.customIcon = customIcon
        // Dates are stored as ISO-8601 with whole-second precision; normalizing here keeps
        // in-memory values identical to what is persisted.
        self.createdAt = createdAt.wholeSeconds
        self.lastOpenedAt = lastOpenedAt?.wholeSeconds
        self.openCount = openCount
    }

    /// Secondary text used for search and tooltips (path, host, action description).
    public var detailText: String {
        switch target {
        case .application(let app): return app.path
        case .file(let ref), .folder(let ref): return ref.path
        case .website(let url): return url.absoluteString
        case .action(let action):
            if let text = action.text, !text.isEmpty, action.kind.requiresText {
                return "\(action.kind.title): \(text)"
            }
            return action.kind.subtitle
        }
    }

    /// A key that identifies "the same thing" so the library does not hold duplicates.
    public var deduplicationKey: String {
        switch target {
        case .application(let app):
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                return "app:\(bundleID.lowercased())"
            }
            return "app:\(PathUtilities.standardize(app.path).lowercased())"
        case .file(let ref):
            return "file:\(PathUtilities.standardize(ref.path))"
        case .folder(let ref):
            return "folder:\(PathUtilities.standardize(ref.path))"
        case .website(let url):
            return "web:\(WebAddress.canonicalString(for: url))"
        case .action(let action):
            return "action:\(action.kind.rawValue):\(action.text ?? "")"
        }
    }
}

extension Date {
    /// This date truncated to whole seconds (exactly representable in ISO-8601 JSON).
    public var wholeSeconds: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down)) }
}

// MARK: - Target

/// What a launcher item opens.
public enum ItemTarget: Equatable, Hashable, Sendable {
    case application(AppReference)
    case file(FileReference)
    case folder(FileReference)
    case website(URL)
    case action(ActionReference)

    public var kind: ItemKind {
        switch self {
        case .application: return .application
        case .file: return .file
        case .folder: return .folder
        case .website: return .website
        case .action: return .action
        }
    }

    /// The file-system reference for file and folder targets.
    public var fileReference: FileReference? {
        switch self {
        case .file(let ref), .folder(let ref): return ref
        default: return nil
        }
    }
}

extension ItemTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, app, file, url, action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemKind.self, forKey: .type)
        switch type {
        case .application:
            self = .application(try container.decode(AppReference.self, forKey: .app))
        case .file:
            self = .file(try container.decode(FileReference.self, forKey: .file))
        case .folder:
            self = .folder(try container.decode(FileReference.self, forKey: .file))
        case .website:
            self = .website(try container.decode(URL.self, forKey: .url))
        case .action:
            self = .action(try container.decode(ActionReference.self, forKey: .action))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .application(let app): try container.encode(app, forKey: .app)
        case .file(let ref), .folder(let ref): try container.encode(ref, forKey: .file)
        case .website(let url): try container.encode(url, forKey: .url)
        case .action(let action): try container.encode(action, forKey: .action)
        }
    }
}

/// A reference to an installed application.
///
/// Applications are resolved by path first (so users can pin a specific copy,
/// e.g. a beta), then by bundle identifier (so moved or updated apps are found),
/// then by bookmark.
public struct AppReference: Codable, Equatable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var path: String
    public var bookmark: Data?

    public init(bundleIdentifier: String?, path: String, bookmark: Data? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.bookmark = bookmark
    }
}

/// A reference to a user-selected file or folder.
///
/// `bookmark` is a security-scoped bookmark created while QuickDock had
/// user-granted access (open panel or drag and drop). `path` is the last known
/// location, kept for display and as a fallback.
public struct FileReference: Codable, Equatable, Hashable, Sendable {
    public var path: String
    public var bookmark: Data?

    public init(path: String, bookmark: Data? = nil) {
        self.path = path
        self.bookmark = bookmark
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var lastPathComponent: String { url.lastPathComponent }
}

/// A reference to one of QuickDock's built-in actions.
public struct ActionReference: Codable, Equatable, Hashable, Sendable {
    public var kind: PredefinedAction
    /// Extra input for actions that need it (snippet text, e-mail address).
    public var text: String?

    public init(kind: PredefinedAction, text: String? = nil) {
        self.kind = kind
        self.text = text
    }
}

// MARK: - Category

/// A user-defined group, e.g. "Work" or "Design".
public struct ItemCategory: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbolName: String

    public init(id: UUID = UUID(), name: String, symbolName: String = "folder") {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    /// Symbols offered when creating a category.
    public static let suggestedSymbols: [String] = [
        "folder", "briefcase", "house", "hammer", "paintbrush", "chevron.left.forwardslash.chevron.right",
        "book", "music.note", "camera", "gamecontroller", "cart", "graduationcap",
        "person.2", "star", "bolt", "globe",
    ]
}

// MARK: - Library snapshot

/// Everything QuickDock persists about the user's items, written to `library.json`.
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [LaunchItem]
    public var categories: [ItemCategory]

    public init(schemaVersion: Int = LibrarySnapshot.currentSchemaVersion,
                items: [LaunchItem] = [],
                categories: [ItemCategory] = []) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.categories = categories
    }

    public static let empty = LibrarySnapshot()
}
