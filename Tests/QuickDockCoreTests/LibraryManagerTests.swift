import Foundation
import Testing
@testable import QuickDockCore

@Suite("Library manager")
@MainActor
struct LibraryManagerTests {
    let dir = TemporaryDirectory()

    func makeManager() -> LibraryManager {
        let manager = LibraryManager(store: LibraryStore(directory: dir.url),
                                     iconStore: IconStore(directory: dir.url.appendingPathComponent("Icons")),
                                     saveDelay: 0)
        manager.load()
        return manager
    }

    @Test("Adding persists and duplicates are rejected")
    func addAndDuplicates() {
        let manager = makeManager()
        guard case .added = manager.add(.website("example.com")) else { Issue.record("should add"); return }
        guard case .duplicate = manager.add(.website("https://EXAMPLE.com/")) else { Issue.record("should dedupe"); return }
        #expect(manager.items.count == 1)
        #expect(makeManager().items.count == 1) // reloaded from disk
    }

    @Test("Batch add reports duplicates")
    func batchAdd() {
        let manager = makeManager()
        manager.add(.website("a.com"))
        let result = manager.add(contentsOf: [.website("a.com"), .website("b.com"), .website("b.com")])
        #expect(result.added.count == 1)
        #expect(result.duplicates.count == 2)
    }

    @Test("Rename, edit and remove persist")
    func editing() {
        let manager = makeManager()
        manager.add(.website("a.com"))
        let id = manager.items[0].id
        manager.rename(id, to: "  My Site  ")
        #expect(manager.items[0].name == "My Site")
        manager.rename(id, to: "   ") // ignored
        #expect(manager.items[0].name == "My Site")

        var edited = manager.items[0]
        edited.customIcon = .symbol(name: "star.fill", tint: .pink)
        manager.update(edited)
        #expect(makeManager().items[0].customIcon == .symbol(name: "star.fill", tint: .pink))

        manager.remove(id)
        #expect(makeManager().items.isEmpty)
    }

    @Test("Drag-and-drop ordering persists")
    func ordering() {
        let manager = makeManager()
        manager.add(contentsOf: ["a.com", "b.com", "c.com", "d.com"].map { LaunchItem.website($0) })
        let ids = manager.items.map(\.id)

        manager.move(ids[3], to: ids[0]) // d before a
        #expect(manager.items.map(\.name) == ["D", "A", "B", "C"])
        manager.move(fromOffsets: IndexSet(integer: 0), toOffset: 4) // d to end
        #expect(manager.items.map(\.name) == ["A", "B", "C", "D"])
        manager.move(fromOffsets: IndexSet([0, 1]), toOffset: 3) // a, b after c
        #expect(manager.items.map(\.name) == ["C", "A", "B", "D"])

        #expect(makeManager().items.map(\.name) == ["C", "A", "B", "D"])
    }

    @Test("Favorites and categories")
    func favoritesAndCategories() throws {
        let manager = makeManager()
        manager.add(contentsOf: [.website("a.com"), .website("b.com")])
        let id = manager.items[0].id
        manager.togglePinned(id)
        #expect(manager.favorites.map(\.id) == [id])

        let work = try #require(manager.addCategory(name: "Work", symbolName: "briefcase"))
        #expect(manager.addCategory(name: "work")?.id == work.id) // no duplicate names
        #expect(manager.addCategory(name: "   ") == nil)
        manager.setCategory(work.id, for: [id])
        #expect(manager.items[0].categoryID == work.id)

        let reloaded = makeManager()
        #expect(reloaded.items[0].isPinned)
        #expect(reloaded.items[0].categoryID == work.id)

        manager.deleteCategory(work.id)
        #expect(manager.items[0].categoryID == nil)
        #expect(manager.items.count == 2) // items survive category deletion
    }

    @Test("Assigning an unknown category is ignored")
    func unknownCategory() {
        let manager = makeManager()
        manager.add(.website("a.com"))
        manager.setCategory(UUID(), for: [manager.items[0].id])
        #expect(manager.items[0].categoryID == nil)
    }

    @Test("Opening updates usage statistics")
    func recordOpen() {
        let manager = makeManager()
        manager.add(.website("a.com"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        manager.recordOpen(manager.items[0].id, at: date)
        #expect(manager.items[0].openCount == 1)
        #expect(makeManager().items[0].lastOpenedAt == date)
    }

    @Test("Pending changes are flushed")
    func debouncedSaveFlush() {
        let manager = LibraryManager(store: LibraryStore(directory: dir.url), saveDelay: 60)
        manager.load()
        manager.add(.website("a.com"))
        #expect(makeManager().items.isEmpty) // not yet written
        manager.flush()
        #expect(makeManager().items.count == 1)
    }

    @Test("Merge matches categories by name and skips duplicates")
    func merge() {
        let manager = makeManager()
        let existingCategory = manager.addCategory(name: "Work")!
        manager.add(.website("a.com"))

        let importedWork = ItemCategory(name: "WORK")
        let importedHome = ItemCategory(name: "Home")
        var b = LaunchItem.website("b.com"); b.categoryID = importedWork.id
        var c = LaunchItem.website("c.com"); c.categoryID = importedHome.id
        let result = manager.merge(items: [.website("a.com"), b, c], categories: [importedWork, importedHome])

        #expect(result.added == 2)
        #expect(result.skipped == 1)
        #expect(manager.categories.count == 2)
        #expect(manager.items.first { $0.name == "B" }?.categoryID == existingCategory.id)
        #expect(manager.items.first { $0.name == "C" }?.categoryID == manager.categories.first { $0.name == "Home" }?.id)
    }

    @Test("Removing an item deletes its custom icon file")
    func iconCleanup() throws {
        let manager = makeManager()
        let iconName = try manager.iconStore!.storeImageData(IconStoreTests.tinyPNG)
        var item = LaunchItem.website("a.com")
        item.customIcon = .image(fileName: iconName)
        manager.add(item)
        #expect(manager.iconStore!.data(for: iconName) != nil)
        manager.remove(manager.items[0].id)
        #expect(manager.iconStore!.data(for: iconName) == nil)
    }

    @Test("Corrupted library is recovered on load and rewritten")
    func recoveryRewrites() throws {
        let manager = makeManager()
        manager.add(.website("a.com"))
        manager.add(.website("b.com"))
        try Data("garbage".utf8).write(to: manager.store.fileURL)

        let recovered = LibraryManager(store: LibraryStore(directory: dir.url), saveDelay: 0)
        guard case .recovered = recovered.load() else { Issue.record("expected recovery"); return }
        #expect(recovered.items.map(\.name) == ["A"]) // backup was one save behind
        #expect(LibraryStore(directory: dir.url).load() == .loaded(recovered.snapshot))
    }
}
