import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickDockCore

enum ItemEditorMode {
    enum NewKind { case website, action }
    case edit(LaunchItem)
    case new(NewKind)
}

/// Adds websites and actions, and edits any item (name, location, category, icon).
struct ItemEditorView: View {
    let mode: ItemEditorMode
    /// Closes the window; `true` re-opens the launcher.
    let close: (Bool) -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryManager

    @State private var name = ""
    @State private var address = ""
    @State private var actionKind: PredefinedAction = .copySnippet
    @State private var actionText = ""
    @State private var categoryID: UUID?
    @State private var isPinned = false
    @State private var iconChoice: IconChoice = .standard
    @State private var symbolName = "star.fill"
    @State private var tint: IconTint = .blue
    @State private var imageFileName: String?
    @State private var errorMessage: String?
    @State private var didLoad = false

    enum IconChoice: String, CaseIterable, Identifiable {
        case standard = "Default", symbol = "Symbol", image = "Image"
        var id: String { rawValue }
    }

    private var editingItem: LaunchItem? {
        if case .edit(let item) = mode { return library.item(withID: item.id) ?? item }
        return nil
    }

    private var kind: ItemKind {
        switch mode {
        case .edit(let item): return item.kind
        case .new(.website): return .website
        case .new(.action): return .action
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        ItemIconView(item: previewItem, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.isEmpty ? placeholderName : name).font(.headline).lineLimit(1)
                            Text(kind.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    TextField("Name", text: $name, prompt: Text(placeholderName))
                    targetFields
                }

                Section {
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(library.categories) { category in
                            Label(category.name, systemImage: category.symbolName).tag(UUID?.some(category.id))
                        }
                    }
                    Toggle("Favorite", isOn: $isPinned)
                } footer: {
                    Text("Favorites appear in the Favorites filter and the menu-bar menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Icon") {
                    Picker("Icon", selection: $iconChoice) {
                        ForEach(IconChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    iconOptions
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            HStack {
                if editingItem != nil {
                    Button("Remove…", role: .destructive, action: confirmRemove)
                }
                Spacer()
                Button("Cancel") { close(false) }
                    .keyboardShortcut(.cancelAction)
                Button(editingItem == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .frame(minHeight: 600)
        .onAppear(perform: load)
    }

    // MARK: Sections

    @ViewBuilder
    private var targetFields: some View {
        switch kind {
        case .website:
            TextField("Address", text: $address, prompt: Text("example.com"))
        case .action:
            Picker("Action", selection: $actionKind) {
                ForEach(PredefinedAction.allCases, id: \.self) { action in
                    Label(action.title, systemImage: action.symbolName).tag(action)
                }
            }
            Text(actionKind.subtitle).font(.caption).foregroundStyle(.secondary)
            if actionKind == .copySnippet {
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionKind.textFieldLabel).font(.callout)
                    TextEditor(text: $actionText)
                        .font(.body)
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                }
            } else if actionKind.acceptsText {
                TextField(actionKind.textFieldLabel, text: $actionText, prompt: Text("name@example.com"))
            }
        case .application, .file, .folder:
            if let item = editingItem {
                LabeledContent("Location") {
                    HStack {
                        Text(PathUtilities.abbreviate(item.detailText))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(item.detailText)
                        Button("Choose…") {
                            errorMessage = env.adder.relocate(item)
                            NSApp.activateQuickDock()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var iconOptions: some View {
        switch iconChoice {
        case .standard:
            Text(defaultIconDescription).font(.caption).foregroundStyle(.secondary)
        case .symbol:
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 12), spacing: 6) {
                ForEach(IconSymbols.all, id: \.self) { symbol in
                    Button {
                        symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(symbolName == symbol ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                    .accessibilityLabel(symbol)
                }
            }
            HStack(spacing: 8) {
                ForEach(IconTint.allCases, id: \.self) { option in
                    Button { tint = option } label: {
                        Circle().fill(option.color).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.primary, lineWidth: tint == option ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(option.displayName)
                    .accessibilityLabel("\(option.displayName) color")
                }
            }
            .padding(.vertical, 4)
        case .image:
            HStack {
                Text(imageFileName == nil ? "No image chosen" : "Custom image")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose Image…", action: chooseImage)
            }
        }
    }

    // MARK: Data

    private var placeholderName: String {
        switch kind {
        case .website:
            if let url = try? WebAddress.normalize(address) { return ItemFactory.defaultWebsiteName(for: url) }
            return "Website name"
        case .action: return actionKind.title
        default: return editingItem?.name ?? "Name"
        }
    }

    private var defaultIconDescription: String {
        switch kind {
        case .application: return "Uses the application’s own icon."
        case .file, .folder: return "Uses the icon shown in Finder."
        case .website: return "A colored tile with the site’s initial. QuickDock never downloads website icons."
        case .action: return "Uses the action’s symbol."
        }
    }

    private var customIcon: CustomIcon? {
        switch iconChoice {
        case .standard: return nil
        case .symbol: return .symbol(name: symbolName, tint: tint)
        case .image: return imageFileName.map { .image(fileName: $0) }
        }
    }

    /// A live preview of the item being edited.
    private var previewItem: LaunchItem {
        var item = editingItem ?? LaunchItem(name: name, target: .action(ActionReference(kind: actionKind)))
        if case .new(.website) = mode {
            item.target = .website((try? WebAddress.normalize(address)) ?? URL(string: "https://example.com")!)
        }
        if case .new(.action) = mode { item.target = .action(ActionReference(kind: actionKind)) }
        if case .action = item.target, editingItem != nil { item.target = .action(ActionReference(kind: actionKind)) }
        if case .website = item.target, editingItem != nil, let url = try? WebAddress.normalize(address) {
            item.target = .website(url)
        }
        item.customIcon = customIcon
        return item
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let item = editingItem else { return }
        name = item.name
        categoryID = item.categoryID
        isPinned = item.isPinned
        switch item.target {
        case .website(let url): address = url.absoluteString
        case .action(let action):
            actionKind = action.kind
            actionText = action.text ?? ""
        default: break
        }
        switch item.customIcon {
        case .symbol(let symbol, let color)?:
            iconChoice = .symbol; symbolName = symbol; tint = color
        case .image(let fileName)?:
            iconChoice = .image; imageFileName = fileName
        case nil:
            iconChoice = .standard
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Icon Image"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .icns, .gif, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            imageFileName = try SecurityScope.access(url) { try env.iconStore.importImage(at: url) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        errorMessage = nil
        if iconChoice == .image && imageFileName == nil {
            errorMessage = "Choose an image, or pick a different icon style."
            return
        }
        do {
            switch mode {
            case .new(.website):
                var item = try env.factory.makeWebsite(address: address, name: name)
                applyCommonFields(to: &item)
                try add(item)
            case .new(.action):
                var item = try env.factory.makeAction(actionKind, text: actionText, name: name)
                applyCommonFields(to: &item)
                try add(item)
            case .edit:
                guard var item = editingItem else { close(false); return }
                switch item.target {
                case .website:
                    item.target = .website(try WebAddress.normalize(address))
                case .action:
                    item.target = .action(try ItemFactory.validatedAction(actionKind, text: actionText))
                default: break
                }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ItemFactory.FactoryError.emptyName }
                item.name = trimmed
                applyCommonFields(to: &item)
                if let duplicate = library.existingItem(matching: item), duplicate.id != item.id {
                    errorMessage = "“\(duplicate.name)” already opens this. Edit that item instead."
                    return
                }
                library.update(item)
                close(false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyCommonFields(to item: inout LaunchItem) {
        item.categoryID = categoryID
        item.isPinned = isPinned
        item.customIcon = customIcon
    }

    private func add(_ item: LaunchItem) throws {
        switch library.add(item) {
        case .added:
            close(true)
        case .duplicate(let existing):
            errorMessage = "“\(existing.name)” is already in QuickDock."
        }
    }

    private func confirmRemove() {
        guard let item = editingItem else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(item.name)” from QuickDock?"
        alert.informativeText = "Only the shortcut is removed. The original app, file or folder isn’t affected."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            library.remove(item.id)
            close(false)
        }
    }
}
