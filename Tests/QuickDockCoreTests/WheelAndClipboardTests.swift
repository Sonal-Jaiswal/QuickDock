import Foundation
import Testing
@testable import QuickDockCore

@Suite("Quick Wheel")
struct WheelLayoutTests {
    func library() -> [LaunchItem] {
        var items = (1...12).map { LaunchItem.website("site\($0).com", name: "S\($0)") }
        items[2].isPinned = true
        items[5].isPinned = true
        items[7].openCount = 9; items[7].lastOpenedAt = Date(timeIntervalSince1970: 100)
        items[1].openCount = 9; items[1].lastOpenedAt = Date(timeIntervalSince1970: 200)
        items[9].openCount = 3
        return items
    }

    @Test("Favorites only shows pinned items")
    func favorites() {
        #expect(WheelLayout.items(from: library(), source: .favorites, slots: 8).map(\.name) == ["S3", "S6"])
    }

    @Test("Most used sorts by count, then recency")
    func frequent() {
        #expect(WheelLayout.items(from: library(), source: .frequent, slots: 8).map(\.name) == ["S2", "S8", "S10"])
    }

    @Test("Mixed mode fills every slot without duplicates")
    func mixed() {
        let names = WheelLayout.items(from: library(), source: .favoritesThenFrequent, slots: 8).map(\.name)
        #expect(names.count == 8)
        #expect(Array(names.prefix(5)) == ["S3", "S6", "S2", "S8", "S10"])
        #expect(Set(names).count == 8)
    }

    @Test("Slot count is clamped")
    func clamp() {
        #expect(WheelLayout.items(from: library(), source: .favoritesThenFrequent, slots: 99).count == 12)
        #expect(WheelLayout.items(from: library(), source: .favoritesThenFrequent, slots: 1).count == 4)
    }

    @Test("Directions map to slots: top is 0, clockwise", arguments: [
        (0.0, 100.0, 0), (100.0, 0.0, 2), (0.0, -100.0, 4), (-100.0, 0.0, 6), (70.0, 70.0, 1), (-70.0, 70.0, 7),
    ])
    func directions(dx: Double, dy: Double, expected: Int) {
        #expect(WheelLayout.slot(dx: dx, dy: dy, count: 8) == expected)
    }

    @Test("Dead zone in the middle selects nothing")
    func deadZone() {
        #expect(WheelLayout.slot(dx: 10, dy: 10, count: 8) == nil)
        #expect(WheelLayout.slot(dx: 0, dy: 100, count: 0) == nil)
    }

    @Test("Slot boundaries are halfway between centres")
    func boundaries() {
        // With 4 slots, slot 1 (right) spans 45°…135°.
        let r = 100.0
        let at = { (degrees: Double) in WheelLayout.slot(dx: r * sin(degrees * .pi / 180), dy: r * cos(degrees * .pi / 180), count: 4) }
        #expect(at(44) == 0)
        #expect(at(46) == 1)
        #expect(at(134) == 1)
        #expect(at(316) == 0)
    }
}

@Suite("Quick Wheel hold gesture")
struct WheelHoldTests {
    @Test("Letting go with a slot highlighted opens it, however long the hold")
    func opensHighlighted() {
        #expect(WheelLayout.holdOutcome(highlighted: 2, heldFor: 0.1) == .open(2))
        #expect(WheelLayout.holdOutcome(highlighted: 0, heldFor: 5) == .open(0))
    }

    @Test("A quick tap with nothing highlighted keeps the wheel open")
    func tapStaysOpen() {
        #expect(WheelLayout.holdOutcome(highlighted: nil, heldFor: 0.2) == .stayOpen)
    }

    @Test("A long hold with nothing highlighted cancels")
    func longHoldCancels() {
        #expect(WheelLayout.holdOutcome(highlighted: nil, heldFor: 1.0) == .cancel)
    }
}

@Suite("Clipboard history")
struct ClipboardHistoryTests {
    @Test("Records newest first and moves repeats to the top")
    func ordering() {
        var history = ClipboardHistory()
        history.record("one"); history.record("two"); history.record("one")
        #expect(history.ordered.map(\.text) == ["one", "two"])
    }

    @Test("Ignores empty and oversized text")
    func ignored() {
        var history = ClipboardHistory()
        let blank = history.record("   \n ")
        let huge = history.record(String(repeating: "x", count: ClipboardHistory.maximumTextLength + 1))
        #expect(!blank)
        #expect(!huge)
        #expect(history.entries.isEmpty)
    }

    @Test("Trims to the limit but keeps pinned entries")
    func limit() {
        var history = ClipboardHistory(limit: 10)
        history.record("keep")
        history.togglePin(history.entries[0].id)
        for i in 0..<30 { history.record("item \(i)") }
        #expect(history.entries.count == 11)
        #expect(history.ordered.first?.text == "keep")
        #expect(history.ordered[1].text == "item 29")
    }

    @Test("Clear keeps pinned entries; remove deletes one")
    func clearing() {
        var history = ClipboardHistory()
        history.record("a"); history.record("b")
        history.togglePin(history.entries[1].id) // "a"
        history.clearUnpinned()
        #expect(history.entries.map(\.text) == ["a"])
        history.remove(history.entries[0].id)
        #expect(history.entries.isEmpty)
    }

    @Test("Password-manager and transient copies are ignored")
    func privacyTypes() {
        #expect(ClipboardHistory.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardHistory.shouldIgnore(pasteboardTypes: ["org.nspasteboard.TransientType"]))
        #expect(!ClipboardHistory.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"]))
    }

    @Test("Search and preview")
    func searchAndPreview() {
        var history = ClipboardHistory()
        history.record("Hello World"); history.record("Résumé link\nsecond line")
        #expect(history.search("resume").map(\.text) == ["Résumé link\nsecond line"])
        #expect(history.entries[0].preview == "Résumé link ⏎ second line")
    }

    @Test("Store round trip and delete")
    func store() throws {
        let dir = TemporaryDirectory()
        let store = ClipboardStore(directory: dir.url)
        var history = ClipboardHistory(limit: 20)
        history.record("saved", sourceApp: "Notes")
        try store.save(history)
        #expect(store.load() == history)
        store.delete()
        #expect(store.load() == nil)
    }
}

@Suite("Wheel and clipboard preferences")
@MainActor
struct WheelPreferencesTests {
    @Test("Defaults, persistence and clamping")
    func preferences() {
        let name = "QuickDockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.wheelHotKey == .defaultWheel)
        #expect(!prefs.clipboardHistoryEnabled) // opt-in
        #expect(!prefs.clipboardRemember)
        prefs.wheelSlots = 50
        prefs.clipboardHistoryEnabled = true
        prefs.wheelHotKey = nil
        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.wheelSlots == WheelLayout.slotRange.upperBound)
        #expect(reloaded.clipboardHistoryEnabled)
        #expect(reloaded.wheelHotKey == nil)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Older exports without wheel settings still import")
    func tolerantDecoding() throws {
        let json = #"{"appearance":"dark","gridColumns":7}"#
        let snapshot = try JSONDecoder().decode(PreferencesSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.appearance == .dark)
        #expect(snapshot.gridColumns == 7)
        #expect(snapshot.wheelHotKey == .defaultWheel)
        #expect(snapshot.hotKey == .defaultLauncher)
    }

    @Test("Wheel shortcut can't duplicate the launcher shortcut")
    func noDuplicateShortcut() {
        let snapshot = PreferencesSnapshot(hotKey: .defaultWheel, wheelHotKey: .defaultWheel).sanitized()
        #expect(snapshot.wheelHotKey == nil)
    }
}
