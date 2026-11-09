import Foundation
import Combine

/// The in-memory library of items and categories, with persistence.
///
/// All mutations go through this type. Changes are saved shortly after they
/// happen (coalescing bursts such as drag reordering) and flushed on quit.
@MainActor
public final class LibraryManager: ObservableObject {
    public enum AddResult: Equatable {
        case added(LaunchItem)
        case duplicate(existing: LaunchItem)
    }

    @Published public private(set) var items: [LaunchItem] = []
    @Published public private(set) var categories: [ItemCategory] = []
    /// Set when saving fails; the UI surfaces it. Cleared after the next successful save.
    @Published public private(set) var saveError: String?

    public let store: LibraryStore
    public let iconStore: IconStore?
    /// Delay before a change is written. Zero writes synchronously (used in tests).
    public var saveDelay: TimeInterval

    private var pendingSave: DispatchWorkItem?

    public init(store: LibraryStore, iconStore: IconStore? = nil, saveDelay: TimeInterval = 0.4) {
        self.store = store
        self.iconStore = iconStore
        self.saveDelay = saveDelay
    }

    public var snapshot: LibrarySnapshot {
        LibrarySnapshot(items: items, categories: categories)
    }

    // MARK: Loading and saving

    /// Loads the library from disk. Call once at launch.
    @discardableResult
    public func load() -> LibraryStore.LoadResult {
        let result = store.load()
        switch result {
        case .empty:
            items = []
            categories = []
        case .loaded(let snapshot), .recovered(let snapshot, _, _):
            apply(snapshot)
        }
        if case .recovered = result {
            // Write the recovered data so the main file is valid again.
            saveNow()
        }
        return result
    }

    /// Writes any pending change immediately (call on quit).
    public func flush() {
        guard pendingSave != nil else { return }
        saveNow()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        if saveDelay <= 0 {
            saveNow()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try store.save(snapshot)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        let validCategoryIDs = Set(snapshot.categories.map(\.id))
        var seenIDs = Set<UUID>()
        items = snapshot.items.map { item in
            var item = item
            if let categoryID = item.categoryID, !validCategoryIDs.contains(categoryID) { item.categoryID = nil }
            if seenIDs.contains(item.id) { item.id = UUID() }
            seenIDs.insert(item.id)
            return item
        }
        categories = snapshot.categories
    }

    // MARK: Queries

    public func item(withID id: UUID) -> LaunchItem? {
        items.first { $0.id == id }
    }

    public func existingItem(matching item: LaunchItem) -> LaunchItem? {
        let key = item.deduplicationKey
        return items.first { $0.deduplicationKey == key }
    }

    public var favorites: [LaunchItem] { items.filter(\.isPinned) }

    public func category(withID id: UUID?) -> ItemCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    // MARK: Item mutations

    @discardableResult
    public func add(_ item: LaunchItem) -> AddResult {
        if let existing = existingItem(matching: item) {
            return .duplicate(existing: existing)
        }
        var item = item
        if items.contains(where: { $0.id == item.id }) { item.id = UUID() }
        if category(withID: item.categoryID) == nil { item.categoryID = nil }
        items.append(item)
        scheduleSave()
        return .added(item)
    }

    /// Adds several items, skipping duplicates.
    @discardableResult
    public func add(contentsOf newItems: [LaunchItem]) -> (added: [LaunchItem], duplicates: [LaunchItem]) {
        var added: [LaunchItem] = []
        var duplicates: [LaunchItem] = []
        for item in newItems {
            switch add(item) {
            case .added(let item): added.append(item)
            case .duplicate(let existing): duplicates.append(existing)
            }
        }
        return (added, duplicates)
    }

    public func update(_ item: LaunchItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var item = item
        item.name = ItemFactory.clampName(item.name)
        if item.name.isEmpty { item.name = items[index].name }
        if category(withID: item.categoryID) == nil { item.categoryID = nil }
        let oldIcon = items[index].customIcon
        items[index] = item
        if case .image(let oldFile) = oldIcon, oldIcon != item.customIcon {
            iconStore?.delete(oldFile)
        }
        scheduleSave()
    }

    public func rename(_ id: UUID, to name: String) {
        guard var item = item(withID: id) else { return }
        let clean = ItemFactory.clampName(name)
        guard !clean.isEmpty else { return }
        item.name = clean
        update(item)
    }

    /// Updates only the target (used when a moved file is found or a bookmark is refreshed).
    public func updateTarget(_ id: UUID, to target: ItemTarget) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].target != target else { return }
        items[index].target = target
        scheduleSave()
    }

    public func remove(ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        for item in removed {
            if case .image(let fileName) = item.customIcon { iconStore?.delete(fileName) }
        }
        scheduleSave()
    }

    public func remove(_ id: UUID) { remove(ids: [id]) }

    /// Reorders using list offsets (SwiftUI `onMove`).
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy({ items.indices.contains($0) }) else { return }
        let destination = min(max(destination, 0), items.count)
        let moving = source.map { items[$0] }
        var remaining = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(max(insertAt, 0), remaining.count))
        guard remaining != items else { return }
        items = remaining
        scheduleSave()
    }

    /// Moves `id` to the position currently occupied by `targetID` (grid drag and drop).
    public func move(_ id: UUID, to targetID: UUID) {
        guard id != targetID,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        scheduleSave()
    }

    public func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isPinned != pinned else { return }
        items[index].isPinned = pinned
        scheduleSave()
    }

    public func togglePinned(_ id: UUID) {
        guard let item = item(withID: id) else { return }
        setPinned(id, !item.isPinned)
    }

    public func setCategory(_ categoryID: UUID?, for ids: Set<UUID>) {
        let validID = category(withID: categoryID)?.id
        var changed = false
        for index in items.indices where ids.contains(items[index].id) && items[index].categoryID != validID {
            items[index].categoryID = validID
            changed = true
        }
        if changed { scheduleSave() }
    }

    public func recordOpen(_ id: UUID, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastOpenedAt = date.wholeSeconds
        items[index].openCount += 1
        scheduleSave()
    }

    // MARK: Categories

    nonisolated public static let maximumCategoryNameLength = 40

    @discardableResult
    public func addCategory(name: String, symbolName: String = "folder") -> ItemCategory? {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCategoryNameLength))
        guard !clean.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            return existing
        }
        let category = ItemCategory(name: clean, symbolName: symbolName)
        categories.append(category)
        scheduleSave()
        return category
    }

    public func updateCategory(_ category: ItemCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        var category = category
        category.name = String(category.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCategoryNameLength))
        guard !category.name.isEmpty else { return }
        categories[index] = category
        scheduleSave()
    }

    /// Deletes a category. Its items are kept and become uncategorized.
    public func deleteCategory(_ id: UUID) {
        guard categories.contains(where: { $0.id == id }) else { return }
        categories.removeAll { $0.id == id }
        for index in items.indices where items[index].categoryID == id {
            items[index].categoryID = nil
        }
        scheduleSave()
    }

    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy({ categories.indices.contains($0) }) else { return }
        let moving = source.map { categories[$0] }
        var remaining = categories.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = min(max(destination - source.filter { $0 < destination }.count, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertAt)
        categories = remaining
        scheduleSave()
    }

    // MARK: Bulk operations

    /// Replaces the whole library (import in "Replace" mode).
    public func replaceAll(with snapshot: LibrarySnapshot) {
        let oldIcons = Set(items.compactMap(\.customIconFileName))
        apply(snapshot)
        let newIcons = Set(items.compactMap(\.customIconFileName))
        for name in oldIcons.subtracting(newIcons) { iconStore?.delete(name) }
        saveNow()
    }

    /// Merges items and categories (import in "Merge" mode). Categories are matched by name;
    /// items already in the library are skipped.
    @discardableResult
    public func merge(items newItems: [LaunchItem], categories newCategories: [ItemCategory]) -> (added: Int, skipped: Int) {
        var categoryMap: [UUID: UUID] = [:]
        for category in newCategories {
            if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(category.name) == .orderedSame }) {
                categoryMap[category.id] = existing.id
            } else {
                var copy = category
                if categories.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
                categories.append(copy)
                categoryMap[category.id] = copy.id
            }
        }
        var added = 0
        var skipped = 0
        for var item in newItems {
            item.categoryID = item.categoryID.flatMap { categoryMap[$0] }
            if existingItem(matching: item) != nil {
                skipped += 1
                if case .image(let fileName) = item.customIcon { iconStore?.delete(fileName) }
                continue
            }
            if items.contains(where: { $0.id == item.id }) { item.id = UUID() }
            items.append(item)
            added += 1
        }
        saveNow()
        return (added, skipped)
    }

    /// Removes every item and category.
    public func removeEverything() {
        items = []
        categories = []
        iconStore?.deleteAll()
        saveNow()
    }

    /// Deletes icon files no longer referenced by any item.
    public func cleanUpUnusedIcons() {
        iconStore?.removeUnused(keeping: Set(items.compactMap(\.customIconFileName)))
    }
}

extension LaunchItem {
    public var customIconFileName: String? {
        if case .image(let fileName) = customIcon { return fileName }
        return nil
    }
}
