import Foundation
import Testing
@testable import QuickDockCore

@Suite("Search")
struct SearchTests {
    let items: [LaunchItem] = [
        .app("Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        .app("Safari", bundleID: "com.apple.Safari"),
        .app("System Settings", bundleID: "com.apple.systempreferences"),
        .file("/Users/me/Documents/Résumé.pdf"),
        .folder("/Users/me/Projects"),
        .website("github.com", name: "GitHub"),
        LaunchItem(name: "Email Sign-off", target: .action(ActionReference(kind: .copySnippet, text: "Best"))),
    ]

    @Test("Ranking prefers exact, prefix, word, initials, substring, subsequence")
    func ranking() {
        let exact = SearchMatcher.score(query: "safari", candidate: "Safari")!
        let prefix = SearchMatcher.score(query: "saf", candidate: "Safari")!
        let word = SearchMatcher.score(query: "studio", candidate: "Visual Studio Code")!
        let initials = SearchMatcher.score(query: "vsc", candidate: "Visual Studio Code")!
        let substring = SearchMatcher.score(query: "fari", candidate: "Safari")!
        let fuzzy = SearchMatcher.score(query: "sfr", candidate: "Safari")!
        #expect(exact > prefix)
        #expect(prefix > word)
        #expect(word > initials)
        #expect(initials > substring)
        #expect(substring > fuzzy)
        #expect(SearchMatcher.score(query: "xyz", candidate: "Safari") == nil)
    }

    @Test("Matching ignores case and accents")
    func diacritics() {
        let results = ItemQuery(text: "resume").apply(to: items)
        #expect(results.first?.name == "Résumé.pdf")
    }

    @Test("Empty query keeps user order")
    func emptyQuery() {
        #expect(ItemQuery().apply(to: items) == items)
        #expect(ItemQuery(text: "   ").apply(to: items) == items)
    }

    @Test("Filters by type", arguments: ItemFilter.allCases)
    func filters(filter: ItemFilter) {
        let results = ItemQuery(filter: filter).apply(to: items)
        #expect(results.allSatisfy(filter.matches))
        switch filter {
        case .all: #expect(results.count == items.count)
        case .applications: #expect(results.count == 3)
        case .files, .folders, .websites, .actions: #expect(results.count == 1)
        case .favorites: #expect(results.isEmpty)
        }
    }

    @Test("Filters by category and favorites together with search")
    func combined() {
        let work = UUID()
        var tagged = items
        tagged[1].categoryID = work
        tagged[1].isPinned = true
        tagged[5].categoryID = work
        #expect(ItemQuery(categoryID: work).apply(to: tagged).map(\.name) == ["Safari", "GitHub"])
        #expect(ItemQuery(filter: .favorites, categoryID: work).apply(to: tagged).map(\.name) == ["Safari"])
        #expect(ItemQuery(text: "git", categoryID: work).apply(to: tagged).map(\.name) == ["GitHub"])
    }

    @Test("Secondary text (host, file name) is searchable")
    func secondary() {
        var renamed = items
        renamed[5].name = "Code hosting"
        #expect(ItemQuery(text: "github").apply(to: renamed).first?.name == "Code hosting")
    }
}

@Suite("Keyboard shortcuts")
struct KeyComboTests {
    @Test func defaults() {
        #expect(KeyCombo.defaultLauncher.displayString == "⌥Space")
        #expect(KeyCombo.defaultLauncher.validate() == .valid)
        #expect(KeyCombo.defaultLauncher.modifiers.carbonFlags == 0x0800)
        #expect(KeyCombo(keyCode: KeyCodes.k, modifiers: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘K")
    }

    @Test("Invalid combinations are rejected")
    func invalid() {
        let cases: [KeyCombo] = [
            KeyCombo(keyCode: KeyCodes.a, modifiers: []),
            KeyCombo(keyCode: KeyCodes.a, modifiers: [.shift]),
            KeyCombo(keyCode: KeyCodes.q, modifiers: [.command]),
            KeyCombo(keyCode: KeyCodes.c, modifiers: [.command, .shift]),
            KeyCombo(keyCode: KeyCodes.tab, modifiers: [.command]),
            KeyCombo(keyCode: 0x37, modifiers: [.option]), // Command key itself
        ]
        for combo in cases {
            guard case .invalid = combo.validate() else {
                Issue.record("\(combo.displayString) should be invalid")
                continue
            }
        }
    }

    @Test("System shortcuts produce warnings")
    func warnings() {
        guard case .warning(let message) = KeyCombo(keyCode: KeyCodes.space, modifiers: [.command]).validate() else {
            Issue.record("⌘Space should warn")
            return
        }
        #expect(message.contains("Spotlight"))
    }

    @Test("Function keys work without modifiers")
    func functionKeys() {
        #expect(KeyCombo(keyCode: 0x69, modifiers: []).validate() == .valid) // F13
        #expect(KeyCodes.name(for: 0x69) == "F13")
    }

    @Test func codable() throws {
        let combo = KeyCombo(keyCode: KeyCodes.k, modifiers: [.control, .option])
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
    }
}
