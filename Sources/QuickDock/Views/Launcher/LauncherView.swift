import SwiftUI
import UniformTypeIdentifiers
import QuickDockCore

struct LauncherView: View {
    @ObservedObject var model: LauncherViewModel
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var hotKeys: HotKeyCenter
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false

    private var metrics: LauncherMetrics { LauncherMetrics(preferences: preferences) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            FilterBar(model: model)
                .padding(.horizontal, LauncherMetrics.horizontalPadding)
                .frame(height: 40, alignment: .top)
            Divider().opacity(0.6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.6)
            LauncherFooter(model: model)
                .frame(height: LauncherMetrics.footerHeight)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) {
            if let banner = model.banner {
                BannerView(banner: banner, model: model)
                    .padding(.horizontal, 14)
                    .padding(.bottom, LauncherMetrics.footerHeight + 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: LauncherBackground.cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.banner)
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            SearchField(text: $model.searchText,
                        placeholder: library.items.isEmpty ? "Add items to get started" : "Search QuickDock",
                        focusToken: model.focusToken)
                .frame(height: 30)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    model.requestSearchFocus()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            } else if let combo = hotKeys.currentCombo, hotKeys.isRegistered {
                Keycap(text: KeyboardLayout.displayString(for: combo))
                    .help("Press \(KeyboardLayout.displayString(for: combo)) anywhere to open QuickDock")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.results.isEmpty {
            LauncherEmptyState(model: model)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: LauncherMetrics.gridSpacing),
                                             count: metrics.columns),
                              spacing: 6) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                            ItemTile(item: item, index: index, model: model, metrics: metrics)
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, LauncherMetrics.horizontalPadding)
                }
                .onChange(of: model.selectedID) { id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    // MARK: Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        let urlProviders = providers.filter {
            !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) && $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        guard !fileProviders.isEmpty || !urlProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var fileURLs: [URL] = []
        var webURLs: [URL] = []
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); fileURLs.append(url); lock.unlock() }
                group.leave()
            }
        }
        for provider in urlProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, !url.isFileURL { lock.lock(); webURLs.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            model.handleDrop(fileURLs: fileURLs, webURLs: webURLs)
        }
        return true
    }
}

// MARK: - Filter bar

struct FilterBar: View {
    @ObservedObject var model: LauncherViewModel
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ItemFilter.allCases) { filter in
                FilterChip(title: filter.title, symbol: filter.symbolName, isSelected: model.filter == filter) {
                    model.filter = filter
                    model.requestSearchFocus()
                }
            }
            Spacer(minLength: 8)
            if !library.categories.isEmpty {
                categoryMenu
            }
        }
    }

    private var categoryMenu: some View {
        let current = library.category(withID: model.categoryID)
        return Menu {
            Button {
                model.categoryID = nil
            } label: {
                if model.categoryID == nil { Label("All Categories", systemImage: "checkmark") } else { Text("All Categories") }
            }
            Divider()
            ForEach(library.categories) { category in
                Button {
                    model.categoryID = category.id
                } label: {
                    if model.categoryID == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Label(category.name, systemImage: category.symbolName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: current?.symbolName ?? "line.3.horizontal.decrease")
                Text(current?.name ?? "Categories")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(current == nil ? .secondary : .primary)
        .help("Show one category")
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : .clear))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Footer

private struct LauncherFooter: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        HStack(spacing: 10) {
            if let item = model.selectedItem {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(detail(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(model.hasAnyItems ? " " : "Drop apps, files, folders or links here")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.selectedItem != nil {
                HStack(spacing: 4) {
                    Keycap(text: "↩")
                    Text("Open").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Menu {
                Button("Add Applications…") { model.addApplications() }
                Button("Add Files or Folders…") { model.addFilesAndFolders() }
                Button("Add Website…") { model.addWebsite() }
                Button("Add Action…") { model.addAction() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add items")
            .accessibilityLabel("Add items")

            Menu {
                Button("Settings…") {
                    model.controller?.perform(reopenAfter: false) { model.env.windows.showSettings(); return nil }
                }
                Button("Keyboard Shortcuts…") {
                    model.controller?.perform(reopenAfter: false) { model.env.windows.showSettings(section: .shortcuts); return nil }
                }
                Divider()
                Button("Quit QuickDock") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 18)
    }

    private func detail(for item: LaunchItem) -> String {
        switch item.target {
        case .application(let app): return PathUtilities.abbreviate(app.path)
        case .file(let ref), .folder(let ref): return PathUtilities.abbreviate(ref.path)
        case .website(let url): return url.absoluteString
        case .action(let action): return action.kind.subtitle
        }
    }
}

// MARK: - Banner

private struct BannerView: View {
    let banner: LauncherViewModel.Banner
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .problem(let item, _) = banner.kind {
                Button("Locate…") { model.relocate(item) }
                Button("Remove") { model.remove(item) }
            }
            Button {
                model.banner = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private var symbol: String {
        switch banner.kind {
        case .info: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .problem: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .info: return .green
        case .error: return .red
        case .problem: return .orange
        }
    }

    private var message: String {
        switch banner.kind {
        case .info(let text), .error(let text): return text
        case .problem(let item, let state): return ItemProblemText.message(for: item, state: state)
        }
    }
}

/// Plain-language descriptions of why an item can't be opened.
enum ItemProblemText {
    static func message(for item: LaunchItem, state: ItemAvailability) -> String {
        switch state {
        case .available:
            return "“\(item.name)” is available."
        case .missing:
            let thing = item.kind == .folder ? "folder" : "file"
            return "The \(thing) for “\(item.name)” can’t be found. It may have been moved, renamed or deleted, or its disk isn’t connected."
        case .applicationNotInstalled:
            return "“\(item.name)” isn’t installed on this Mac any more. Locate it if it was moved, or remove it from QuickDock."
        case .needsAccess:
            return "QuickDock needs your permission to open “\(item.name)”. Choose it once with Locate… to grant access."
        }
    }

    static func shortLabel(for state: ItemAvailability) -> String? {
        switch state {
        case .available: return nil
        case .missing: return "Missing"
        case .applicationNotInstalled: return "Not installed"
        case .needsAccess: return "Needs access"
        }
    }
}
