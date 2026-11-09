import Foundation

/// The type filters shown along the top of the launcher.
public enum ItemFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case favorites
    case applications
    case files
    case folders
    case websites
    case actions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .applications: return "Apps"
        case .files: return "Files"
        case .folders: return "Folders"
        case .websites: return "Web"
        case .actions: return "Actions"
        }
    }

    public var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "star"
        case .applications: return "app"
        case .files: return "doc"
        case .folders: return "folder"
        case .websites: return "globe"
        case .actions: return "bolt"
        }
    }

    public func matches(_ item: LaunchItem) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return item.isPinned
        case .applications: return item.kind == .application
        case .files: return item.kind == .file
        case .folders: return item.kind == .folder
        case .websites: return item.kind == .website
        case .actions: return item.kind == .action
        }
    }
}

/// Instant, local, case- and diacritic-insensitive search.
public enum SearchMatcher {
    /// Normalizes text for matching.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scores how well `query` matches `candidate`. Higher is better; `nil` means no match.
    ///
    /// Ranking: exact > prefix > word prefix > initials ("vsc" → "Visual Studio Code")
    /// > substring > in-order subsequence.
    public static func score(query rawQuery: String, candidate rawCandidate: String) -> Int? {
        let query = normalize(rawQuery)
        let candidate = normalize(rawCandidate)
        guard !query.isEmpty else { return 0 }
        guard !candidate.isEmpty else { return nil }

        if candidate == query { return 1_000 }
        if candidate.hasPrefix(query) { return 900 - min(candidate.count - query.count, 100) }

        let words = candidate.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: { $0.hasPrefix(query) }) { return 700 - min(candidate.count, 100) }

        let initials = String(words.compactMap(\.first))
        if query.count >= 2, initials.hasPrefix(query) { return 650 }

        if candidate.contains(query) { return 500 - min(candidate.count, 100) }

        // Every query character appears in order.
        var index = candidate.startIndex
        var gaps = 0
        for character in query where character != " " {
            guard let found = candidate[index...].firstIndex(of: character) else { return nil }
            gaps += candidate.distance(from: index, to: found)
            index = candidate.index(after: found)
        }
        return max(100, 300 - gaps * 5)
    }
}

/// Combines text search, type filter and category filter.
public struct ItemQuery: Equatable, Sendable {
    public var text: String
    public var filter: ItemFilter
    public var categoryID: UUID?

    public init(text: String = "", filter: ItemFilter = .all, categoryID: UUID? = nil) {
        self.text = text
        self.filter = filter
        self.categoryID = categoryID
    }

    public var isSearching: Bool { !SearchMatcher.normalize(text).isEmpty }

    /// Applies the query. Without search text the user's order is preserved;
    /// with search text results are ranked by relevance (ties keep user order).
    public func apply(to items: [LaunchItem]) -> [LaunchItem] {
        let filtered = items.filter { item in
            filter.matches(item) && (categoryID == nil || item.categoryID == categoryID)
        }
        guard isSearching else { return filtered }

        let scored: [(item: LaunchItem, score: Int, index: Int)] = filtered.enumerated().compactMap { index, item in
            let nameScore = SearchMatcher.score(query: text, candidate: item.name)
            // Secondary text (file name, host, path) counts, but less than the name.
            let detailScore = SearchMatcher.score(query: text, candidate: secondaryText(for: item)).map { $0 / 3 }
            guard let best = [nameScore, detailScore].compactMap({ $0 }).max() else { return nil }
            return (item, best, index)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.item)
    }

    private func secondaryText(for item: LaunchItem) -> String {
        switch item.target {
        case .application(let app):
            return (app.path as NSString).lastPathComponent
        case .file(let ref), .folder(let ref):
            return ref.lastPathComponent
        case .website(let url):
            return WebAddress.displayName(for: url)
        case .action(let action):
            return action.kind.title
        }
    }
}
