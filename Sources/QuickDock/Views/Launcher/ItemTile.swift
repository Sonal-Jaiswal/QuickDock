import SwiftUI
import UniformTypeIdentifiers
import QuickDockCore

/// One item in the launcher grid.
struct ItemTile: View {
    let item: LaunchItem
    let index: Int
    @ObservedObject var model: LauncherViewModel
    let metrics: LauncherMetrics
    @EnvironmentObject private var library: LibraryManager
    @State private var isHovered = false

    private var isSelected: Bool { model.selectedID == item.id }
    private var state: ItemAvailability { model.availability(of: item) }

    var body: some View {
        VStack(spacing: 6) {
            ItemIconView(item: item, size: metrics.iconSize)
                .saturation(state.isAvailable ? 1 : 0)
                .opacity(state.isAvailable ? 1 : 0.5)
                .overlay(alignment: .topTrailing) { badge }
                .scaleEffect(model.draggingID == item.id ? 0.9 : 1)
            if metrics.showLabels {
                Text(item.name)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .frame(width: metrics.cellWidth - 10, height: 28, alignment: .top)
                    .foregroundStyle(state.isAvailable ? .primary : .secondary)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, metrics.showLabels ? 4 : 8)
        .frame(width: metrics.cellWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : (isHovered ? Color.primary.opacity(0.06) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { model.open(item) }
        .help(helpText)
        .contextMenu { contextMenu }
        .onDrag {
            model.draggingID = item.id
            return NSItemProvider(object: ("quickdock-item:" + item.id.uuidString) as NSString)
        }
        .onDrop(of: [.plainText], delegate: ReorderDropDelegate(target: item, model: model))
        .animation(.easeOut(duration: 0.15), value: model.draggingID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { model.open(item) }
    }

    @ViewBuilder
    private var badge: some View {
        if !state.isAvailable {
            Image(systemName: "exclamationmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.orange)
                .font(.system(size: max(14, metrics.iconSize * 0.28)))
                .offset(x: 3, y: -3)
        } else if item.isPinned && model.filter != .favorites {
            Image(systemName: "star.fill")
                .font(.system(size: max(9, metrics.iconSize * 0.17), weight: .bold))
                .foregroundStyle(.yellow)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                .offset(x: 2, y: -2)
        }
    }

    private var helpText: String {
        var text = item.name + "\n" + item.detailText
        if let label = ItemProblemText.shortLabel(for: state) { text += "\n" + label }
        if index < 9 { text += "\n⌘\(index + 1)" }
        return text
    }

    private var accessibilityLabel: String {
        var label = "\(item.name), \(item.kind.displayName)"
        if item.isPinned { label += ", favorite" }
        if let problem = ItemProblemText.shortLabel(for: state) { label += ", \(problem)" }
        return label
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open") { model.open(item) }
        if item.target.fileReference != nil || item.kind == .application {
            Button("Show in Finder") { model.reveal(item) }
        }
        if !state.isAvailable {
            Button("Locate…") { model.relocate(item) }
        }
        Divider()
        Button("Edit…") { model.edit(item) }
        Button(item.isPinned ? "Remove from Favorites" : "Add to Favorites") {
            library.togglePinned(item.id)
        }
        if !library.categories.isEmpty {
            Menu("Category") {
                Button {
                    library.setCategory(nil, for: [item.id])
                } label: {
                    if item.categoryID == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                }
                Divider()
                ForEach(library.categories) { category in
                    Button {
                        library.setCategory(category.id, for: [item.id])
                    } label: {
                        if item.categoryID == category.id { Label(category.name, systemImage: "checkmark") } else { Text(category.name) }
                    }
                }
            }
        }
        Divider()
        Button("Remove from QuickDock") { model.remove(item) }
    }
}

/// Live reordering: as a dragged tile passes over another, the library order updates.
struct ReorderDropDelegate: DropDelegate {
    let target: LaunchItem
    let model: LauncherViewModel

    func validateDrop(info: DropInfo) -> Bool {
        model.draggingID != nil && model.canReorder
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.18)) {
            model.moveDragged(onto: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: model.draggingID != nil ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.draggingID = nil
        return true
    }
}

// MARK: - Empty states

struct LauncherEmptyState: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: 8) { buttons }
                .controlSize(.regular)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        if !model.hasAnyItems { return "square.grid.3x3.square" }
        if model.isSearching { return "magnifyingglass" }
        return model.filter.symbolName
    }

    private var title: String {
        if !model.hasAnyItems { return "Your QuickDock is empty" }
        if model.isSearching { return "No matches for “\(model.searchText.trimmingCharacters(in: .whitespaces))”" }
        switch model.filter {
        case .favorites: return "No favorites yet"
        case .applications: return "No apps yet"
        case .files: return "No files yet"
        case .folders: return "No folders yet"
        case .websites: return "No websites yet"
        case .actions: return "No actions yet"
        case .all: return "Nothing in this category"
        }
    }

    private var subtitle: String {
        if !model.hasAnyItems { return "Add the apps, files, folders and websites you use most — or drop them here." }
        if model.isSearching { return "Try a different name, or check the selected filter and category." }
        switch model.filter {
        case .favorites: return "Right-click any item and choose Add to Favorites, or press ⌘D."
        case .actions: return "Actions copy text snippets, start a new email, open Mission Control and more."
        case .all: return "Assign items to this category from their right-click menu."
        default: return "Add some with the buttons below, or drop them onto this window."
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if model.isSearching {
            Button("Clear Search") {
                model.searchText = ""
                model.requestSearchFocus()
            }
        } else if !model.hasAnyItems {
            Button("Add Applications…") { model.addApplications() }
                .keyboardShortcut(.defaultAction)
            Button("Add Files or Folders…") { model.addFilesAndFolders() }
            Button("Add Website…") { model.addWebsite() }
        } else {
            switch model.filter {
            case .applications: Button("Add Applications…") { model.addApplications() }
            case .files, .folders: Button("Add Files or Folders…") { model.addFilesAndFolders() }
            case .websites: Button("Add Website…") { model.addWebsite() }
            case .actions: Button("Add Action…") { model.addAction() }
            case .favorites, .all: Button("Show All Items") { model.filter = .all; model.categoryID = nil }
            }
        }
    }
}
