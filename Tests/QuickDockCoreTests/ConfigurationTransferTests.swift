import Foundation
import Testing
@testable import QuickDockCore

@Suite("Configuration import/export")
struct ConfigurationTransferTests {
    func sampleSnapshot(iconName: String? = nil) -> LibrarySnapshot {
        let work = ItemCategory(name: "Work", symbolName: "briefcase")
        var app = LaunchItem.app("Notes", bundleID: "com.apple.Notes")
        app.categoryID = work.id
        app.isPinned = true
        if case .application(var ref) = app.target { ref.bookmark = Data("secret".utf8); app.target = .application(ref) }
        var file = LaunchItem(name: "Report", target: .file(FileReference(path: "/Users/me/Report.pdf", bookmark: Data("bm".utf8))))
        if let iconName { file.customIcon = .image(fileName: iconName) }
        return LibrarySnapshot(items: [app, file, .website("example.com"),
                                       LaunchItem(name: "Sig", target: .action(ActionReference(kind: .copySnippet, text: "Thanks!")))],
                               categories: [work])
    }

    @Test("Round trip preserves items, categories and preferences, and strips bookmarks")
    func roundTrip() throws {
        let prefs = PreferencesSnapshot(appearance: .dark, gridColumns: 7)
        let data = try ConfigurationTransfer.export(snapshot: sampleSnapshot(), preferences: prefs, iconStore: nil, appVersion: "0.9.0")
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("bookmark"))

        let plan = try ConfigurationTransfer.parse(data)
        #expect(plan.items.count == 4)
        #expect(plan.categories.map(\.name) == ["Work"])
        #expect(plan.items[0].categoryID == plan.categories[0].id)
        #expect(plan.items[0].isPinned)
        #expect(plan.preferences == prefs)
        #expect(plan.fileItemCount == 1)
        #expect(plan.warnings.isEmpty)
    }

    @Test("Custom image icons are embedded and restored")
    func icons() throws {
        let dir = TemporaryDirectory()
        let store = IconStore(directory: dir.url)
        let name = try store.storeImageData(IconStoreTests.tinyPNG)
        let data = try ConfigurationTransfer.export(snapshot: sampleSnapshot(iconName: name), preferences: nil, iconStore: store, appVersion: "1")
        let plan = try ConfigurationTransfer.parse(data)
        let report = try #require(plan.items.first { $0.name == "Report" })
        #expect(report.customIcon == nil) // replaced once the PNG is stored
        #expect(plan.iconImages[report.id] != nil)
    }

    @Test("Rejects files that are not configurations")
    func rejectsGarbage() {
        #expect(throws: ConfigurationTransfer.TransferError.notAConfiguration) { try ConfigurationTransfer.parse(Data("hello".utf8)) }
        #expect(throws: ConfigurationTransfer.TransferError.notAConfiguration) {
            try ConfigurationTransfer.parse(Data(#"{"format":"something.else","version":1}"#.utf8))
        }
        #expect(throws: ConfigurationTransfer.TransferError.notAConfiguration) {
            try ConfigurationTransfer.parse(Data(#"{"format":"quickdock.configuration","version":1,"items":"nope"}"#.utf8))
        }
    }

    @Test("Newer format versions give a clear error")
    func newerVersion() {
        #expect(throws: ConfigurationTransfer.TransferError.unsupportedVersion(7)) {
            try ConfigurationTransfer.parse(Data(#"{"format":"quickdock.configuration","version":7}"#.utf8))
        }
    }

    @Test("Oversized input is rejected")
    func tooLarge() {
        let big = Data(count: ConfigurationTransfer.maximumFileSize + 1)
        #expect(throws: ConfigurationTransfer.TransferError.fileTooLarge) { try ConfigurationTransfer.parse(big) }
    }

    @Test("Unsafe items are dropped with a warning")
    func unsafeItems() throws {
        let json = """
        {"format":"quickdock.configuration","version":1,"exportedAt":"2026-01-01T00:00:00Z","appVersion":"x",
         "categories":[{"id":"\(UUID().uuidString)","name":"  ","symbolName":"folder"}],
         "items":[
          {"item":{"id":"\(UUID().uuidString)","name":"Evil","createdAt":"2026-01-01T00:00:00Z","isPinned":false,"openCount":-5,
                   "target":{"type":"website","url":"javascript:alert(1)"}}},
          {"item":{"id":"\(UUID().uuidString)","name":"Rel","createdAt":"2026-01-01T00:00:00Z","isPinned":false,"openCount":0,
                   "target":{"type":"file","file":{"path":"relative/path.txt"}}}},
          {"item":{"id":"\(UUID().uuidString)","name":"NotApp","createdAt":"2026-01-01T00:00:00Z","isPinned":false,"openCount":0,
                   "target":{"type":"application","app":{"path":"/bin/sh"}}}},
          {"item":{"id":"\(UUID().uuidString)","name":"Mail","createdAt":"2026-01-01T00:00:00Z","isPinned":false,"openCount":0,
                   "target":{"type":"action","action":{"kind":"composeEmail","text":"a@b.com?bcc=x@y.com"}}}},
          {"item":{"id":"\(UUID().uuidString)","name":"","createdAt":"2026-01-01T00:00:00Z","isPinned":false,"openCount":-1,
                   "customIcon":{"type":"symbol","symbol":"../../x","tint":"red"},
                   "target":{"type":"website","url":"https://ok.example.com"}}}
         ]}
        """
        let plan = try ConfigurationTransfer.parse(Data(json.utf8))
        #expect(plan.items.count == 1)
        #expect(plan.items[0].name == "Example") // empty name gets a default
        #expect(plan.items[0].openCount == 0)
        #expect(plan.items[0].customIcon == .symbol(name: "star.fill", tint: .red))
        #expect(plan.categories.isEmpty)
        #expect(plan.warnings.contains { $0.contains("4 items were skipped") })
    }

    @Test("Foreign bookmarks in a crafted file are discarded")
    func foreignBookmarks() throws {
        let json = """
        {"format":"quickdock.configuration","version":1,"exportedAt":"2026-01-01T00:00:00Z","appVersion":"x","categories":[],
         "items":[{"item":{"id":"\(UUID().uuidString)","name":"F","createdAt":"2026-01-01T00:00:00Z","isPinned":false,"openCount":0,
                   "target":{"type":"file","file":{"path":"/tmp/f.txt","bookmark":"\(Data("x".utf8).base64EncodedString())"}}}}]}
        """
        let plan = try ConfigurationTransfer.parse(Data(json.utf8))
        #expect(plan.items[0].target.fileReference?.bookmark == nil)
    }

    @Test("Imported preferences are sanitized")
    func preferencesSanitized() throws {
        let prefs = PreferencesSnapshot(hotKey: KeyCombo(keyCode: KeyCodes.q, modifiers: [.command]), gridColumns: 99, maxVisibleRows: 0)
        let data = try ConfigurationTransfer.export(snapshot: .empty, preferences: prefs, iconStore: nil, appVersion: "1")
        let plan = try ConfigurationTransfer.parse(data)
        #expect(plan.preferences?.gridColumns == AppPreferences.columnRange.upperBound)
        #expect(plan.preferences?.maxVisibleRows == AppPreferences.rowRange.lowerBound)
        #expect(plan.preferences?.hotKey == .defaultLauncher)
    }

    @Test("Duplicate IDs are regenerated")
    func duplicateIDs() throws {
        let item = LaunchItem.website("a.com")
        var twin = LaunchItem.website("b.com")
        twin.id = item.id
        let data = try ConfigurationTransfer.export(snapshot: LibrarySnapshot(items: [item, twin]), preferences: nil, iconStore: nil, appVersion: "1")
        let plan = try ConfigurationTransfer.parse(data)
        #expect(Set(plan.items.map(\.id)).count == 2)
    }
}
