import AppKit
import SwiftUI
import QuickDockCore

/// Manage every item (reorder, edit, remove, favorite, categorize) and the categories themselves.
struct OrganizationSettings: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryManager
    @State private var selection = Set<UUID>()
    @State private var newCategoryName = ""
    @State private var newCategorySymbol = "folder"
    @State private var renamingCategory: ItemCategory?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            itemsSection
            Divider()
            categoriesSection
        }
    }

    // MARK: Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Items").font(.headline)
                Text("\(library.items.count)").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Applications…") { report(env.adder.chooseApplications()?.message) }
                    Button("Files or Folders…") { report(env.adder.chooseFilesAndFolders()?.message) }
                    Button("Website…") { env.windows.showNewItemEditor(kind: .website) }
                    Button("Action…") { env.windows.showNewItemEditor(kind: .action) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .fixedSize()
            }
            if library.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3.square").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No items yet").font(.headline)
                    Text("Use Add to choose apps, files, folders, websites or actions.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(selection: $selection) {
                    ForEach(library.items) { item in
                        ItemRow(item: item, category: library.category(withID: item.categoryID))
                            .tag(item.id)
                            .contextMenu { rowMenu(for: item) }
                    }
                    .onMove { library.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 200)
                .onDeleteCommand { removeSelected() }
                HStack(spacing: 8) {
                    Button("Edit…") { if let id = selection.first, let item = library.item(withID: id) { env.windows.showEditor(for: item) } }
                        .disabled(selection.count != 1)
                    Button("Remove") { removeSelected() }
                        .disabled(selection.isEmpty)
                    if !library.categories.isEmpty {
                        Menu("Move to Category") {
                            Button("None") { library.setCategory(nil, for: selection) }
                            Divider()
                            ForEach(library.categories) { category in
                                Button(category.name) { library.setCategory(category.id, for: selection) }
                            }
                        }
                        .fixedSize()
                        .disabled(selection.isEmpty)
                    }
                    Spacer()
                    Text(message ?? "Drag rows to reorder.").font(.caption).foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func rowMenu(for item: LaunchItem) -> some View {
        Button("Edit…") { env.windows.showEditor(for: item) }
        Button(item.isPinned ? "Remove from Favorites" : "Add to Favorites") { library.togglePinned(item.id) }
        Divider()
        Button("Remove from QuickDock") { library.remove(item.id) }
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = selection.count == 1 ? "Remove this item?" : "Remove \(selection.count) items?"
        alert.informativeText = "Only the shortcuts are removed from QuickDock. Your apps and files aren’t affected."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        library.remove(ids: selection)
        selection.removeAll()
    }

    private func report(_ text: String?) {
        message = text
    }

    // MARK: Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories").font(.headline)
            Text("Group items (for example Work or Personal) and pick a category from the launcher’s filter bar.")
                .font(.caption).foregroundStyle(.secondary)
            if !library.categories.isEmpty {
                List {
                    ForEach(library.categories) { category in
                        HStack {
                            Image(systemName: category.symbolName).frame(width: 20)
                            Text(category.name)
                            Spacer()
                            Text(itemCount(in: category))
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Rename…") { rename(category) }.controlSize(.small)
                            Button {
                                library.deleteCategory(category.id)
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Delete category (its items are kept)")
                                .accessibilityLabel("Delete \(category.name)")
                        }
                    }
                    .onMove { library.moveCategories(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
                .frame(height: min(CGFloat(library.categories.count) * 30 + 12, 150))
            }
            HStack {
                Picker("Symbol", selection: $newCategorySymbol) {
                    ForEach(ItemCategory.suggestedSymbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                .labelsHidden()
                .frame(width: 64)
                TextField("New category name", text: $newCategoryName)
                    .onSubmit(addCategory)
                Button("Add Category", action: addCategory)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    private func itemCount(in category: ItemCategory) -> String {
        let count = library.items.filter { $0.categoryID == category.id }.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func addCategory() {
        guard library.addCategory(name: newCategoryName, symbolName: newCategorySymbol) != nil else { return }
        newCategoryName = ""
    }

    private func rename(_ category: ItemCategory) {
        let alert = NSAlert()
        alert.messageText = "Rename Category"
        let field = NSTextField(string: category.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var updated = category
        updated.name = field.stringValue
        library.updateCategory(updated)
    }
}

private struct ItemRow: View {
    let item: LaunchItem
    let category: ItemCategory?

    var body: some View {
        HStack(spacing: 10) {
            ItemIconView(item: item, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.name)
                    if item.isPinned {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(PathUtilities.abbreviate(item.detailText))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let category {
                Label(category.name, systemImage: category.symbolName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(item.kind.displayName).font(.caption).foregroundStyle(.tertiary).frame(width: 74, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
