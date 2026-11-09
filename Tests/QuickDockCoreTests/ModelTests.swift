import Foundation
import Testing
@testable import QuickDockCore

@Suite("Models")
struct ModelTests {
    @Test("Every target kind round-trips through JSON")
    func targetRoundTrip() throws {
        let items: [LaunchItem] = [
            .app("Safari", bundleID: "com.apple.Safari"),
            .file("/Users/test/Report.pdf"),
            .folder("/Users/test/Projects"),
            .website("https://example.com/docs"),
            LaunchItem(name: "Snippet", target: .action(ActionReference(kind: .copySnippet, text: "Hi there")),
                       categoryID: UUID(), isPinned: true, customIcon: .symbol(name: "star.fill", tint: .orange)),
            LaunchItem(name: "Img", target: .website(URL(string: "https://a.example")!),
                       customIcon: .image(fileName: "\(UUID().uuidString).png")),
        ]
        let snapshot = LibrarySnapshot(items: items, categories: [ItemCategory(name: "Work")])
        let data = try LibraryStore.makeEncoder().encode(snapshot)
        let decoded = try LibraryStore.makeDecoder().decode(LibrarySnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test("JSON uses a stable, readable shape")
    func jsonShape() throws {
        let item = LaunchItem.website("example.com")
        let json = String(decoding: try LibraryStore.makeEncoder().encode(item), as: UTF8.self)
        #expect(json.contains("\"type\" : \"website\""))
        #expect(json.contains("\"url\" : \"https:\\/\\/example.com\""))
    }

    @Test("Unknown target type fails to decode instead of guessing")
    func unknownType() {
        let json = #"{"type":"shell","command":"rm -rf /"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ItemTarget.self, from: Data(json.utf8))
        }
    }

    @Test("Deduplication keys identify the same thing")
    func deduplicationKeys() {
        #expect(LaunchItem.app("A", bundleID: "com.x.App").deduplicationKey
                == LaunchItem.app("B", bundleID: "COM.X.APP", path: "/Other/A.app").deduplicationKey)
        #expect(LaunchItem.file("/tmp/a/../a/file.txt").deduplicationKey == LaunchItem.file("/tmp/a/file.txt").deduplicationKey)
        #expect(LaunchItem.website("https://Example.com/").deduplicationKey == LaunchItem.website("example.com").deduplicationKey)
        #expect(LaunchItem.file("/tmp/x").deduplicationKey != LaunchItem.folder("/tmp/x").deduplicationKey)
    }

    @Test("Icon tint for a host is stable")
    func stableTint() {
        #expect(IconTint.stable(for: "github.com") == IconTint.stable(for: "GitHub.com"))
    }
}

@Suite("Web addresses")
struct WebAddressTests {
    @Test("Bare domains get https", arguments: [
        ("example.com", "https://example.com"),
        ("  example.com/docs?q=1  ", "https://example.com/docs?q=1"),
        ("http://example.com", "http://example.com"),
        ("HTTPS://Example.com/Path", "HTTPS://Example.com/Path"),
        ("localhost:3000", "https://localhost:3000"),
        ("sub.domain.co.uk:8080/x", "https://sub.domain.co.uk:8080/x"),
    ])
    func normalize(input: String, expected: String) throws {
        #expect(try WebAddress.normalize(input).absoluteString == expected)
    }

    @Test("Non-web schemes are rejected", arguments: [
        "javascript:alert(1)", "file:///etc/passwd", "ftp://example.com", "mailto:a@b.com",
        "x-apple.systempreferences:com.apple.preference", "vnc://host", "ssh://host",
    ])
    func rejectsSchemes(input: String) {
        #expect(throws: WebAddress.ValidationError.self) { try WebAddress.normalize(input) }
    }

    @Test("Garbage is rejected", arguments: ["", "   ", "hello", "http://", "https:// space.com"])
    func rejectsGarbage(input: String) {
        #expect(throws: WebAddress.ValidationError.self) { try WebAddress.normalize(input) }
    }

    @Test func displayName() {
        #expect(WebAddress.displayName(for: URL(string: "https://www.apple.com/mac")!) == "apple.com")
    }
}

@Suite("Predefined actions")
struct PredefinedActionTests {
    @Test func mailto() {
        #expect(PredefinedAction.mailtoURL(recipient: nil)?.absoluteString == "mailto:")
        #expect(PredefinedAction.mailtoURL(recipient: "me@example.com")?.absoluteString == "mailto:me@example.com")
        #expect(PredefinedAction.mailtoURL(recipient: "me@example.com?bcc=evil@x.com") == nil)
        #expect(PredefinedAction.mailtoURL(recipient: "not an email") == nil)
    }

    @Test func snippetRequiresText() {
        #expect(throws: ItemFactory.FactoryError.self) { try ItemFactory().makeAction(.copySnippet, text: "") }
        let item = try? ItemFactory().makeAction(.copySnippet, text: String(repeating: "x", count: 20_000))
        if case .action(let action)? = item?.target {
            #expect(action.text?.count == PredefinedAction.maximumTextLength)
        } else {
            Issue.record("Expected an action")
        }
    }

    @Test func systemActionsHaveFallbacks() {
        for action in PredefinedAction.allCases where action.systemAppBundleIdentifier != nil {
            #expect(!action.systemAppFallbackPaths.isEmpty)
        }
    }
}
