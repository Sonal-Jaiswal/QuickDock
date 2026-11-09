import AppKit
import Combine
import QuickDockCore

/// State and behaviour of the launcher panel.
@MainActor
final class LauncherViewModel: ObservableObject {
    struct Banner: Identifiable, Equatable {
        enum Kind: Equatable {
            case info(String)
            case error(String)
            /// An item that couldn't be opened, with recovery actions.
            case problem(LaunchItem, ItemAvailability)
        }
        let id = UUID()
        let kind: Kind
    }

    @Published var searchText = "" {
        didSet { if searchText != oldValue { recompute(resetSelection: true) } }
    }
    @Published var filter: ItemFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            env.preferences.lastFilter = filter
            recompute(resetSelection: true)
        }
    }
    @Published var categoryID: UUID? {
        didSet { if categoryID != oldValue { recompute(resetSelection: true) } }
    }
    @Published private(set) var results: [LaunchItem] = []
    @Published var selectedID: UUID?
    @Published private(set) var availability: [UUID: ItemAvailability] = [:]
    @Published var banner: Banner? {
        didSet { scheduleBannerDismissal() }
    }
    @Published private(set) var focusToken = 0
    /// The item being dragged for reordering.
    @Published var draggingID: UUID?

    var isShowingContextMenu = false
    weak var controller: LauncherController?

    let env: AppEnvironment
    private var cancellables = Set<AnyCancellable>()
    private var bannerTask: Task<Void, Never>?

    init(env: AppEnvironment) {
        self.env = env
        env.library.$items
            .sink { [weak self] items in
                // Defer so `library.items` reflects the new value when recomputing.
                DispatchQueue.main.async { self?.recompute(resetSelection: false) }
                _ = items
            }
            .store(in: &cancellables)
        env.library.$categories
            .sink { [weak self] categories in
                guard let self, let id = self.categoryID, !categories.contains(where: { $0.id == id }) else { return }
                self.categoryID = nil
            }
            .store(in: &cancellables)
    }

    var columns: Int { env.preferences.gridColumns }
    var query: ItemQuery { ItemQuery(text: searchText, filter: filter, categoryID: categoryID) }
    var isSearching: Bool { query.isSearching }
    var hasAnyItems: Bool { !env.library.items.isEmpty }
    /// Reordering by drag is disabled while results are ranked by a search.
    var canReorder: Bool { !isSearching }

    var selectedItem: LaunchItem? {
        guard let selectedID else { return nil }
        return results.first { $0.id == selectedID }
    }

    func availability(of item: LaunchItem) -> ItemAvailability {
        availability[item.id] ?? .available
    }

    // MARK: Presentation

    func prepareForPresentation() {
        searchText = ""
        filter = env.preferences.initialFilter
        if case .problem? = banner?.kind { banner = nil }
        recompute(resetSelection: true)
        refreshAvailability()
    }

    func didHide() {
        draggingID = nil
    }

    func requestSearchFocus() { focusToken += 1 }

    private func recompute(resetSelection: Bool) {
        results = query.apply(to: env.library.items)
        if resetSelection || selectedItem == nil {
            selectedID = results.first?.id
        }
    }

    /// Checks every item on a background queue (bookmark resolution can touch the disk)
    /// and stores refreshed locations for moved files and apps.
    func refreshAvailability() {
        let items = env.library.items
        let resolver = env.resolver
        Task.detached(priority: .userInitiated) {
            var resolutions: [UUID: ItemResolution] = [:]
            for item in items { resolutions[item.id] = resolver.resolve(item.target) }
            let resolved = resolutions
            await MainActor.run { [weak self] in
                guard let self else { return }
                var map: [UUID: ItemAvailability] = [:]
                for (id, resolution) in resolved {
                    map[id] = resolution.availability
                    if let updated = resolution.updatedTarget { self.env.library.updateTarget(id, to: updated) }
                }
                self.availability = map
            }
        }
    }

    // MARK: Selection

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? -1
        var next = current + offset
        if current < 0 { next = 0 }
        next = min(max(next, 0), results.count - 1)
        selectedID = results[next].id
    }

    func cycleFilter(forward: Bool) {
        let all = ItemFilter.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        filter = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }

    // MARK: Opening

    func openSelected() {
        if let item = selectedItem { open(item) }
    }

    func openItem(atVisibleIndex index: Int) {
        guard results.indices.contains(index) else { return }
        open(results[index])
    }

    func open(_ item: LaunchItem) {
        selectedID = item.id
        Task {
            let outcome = await env.launcher.open(item)
            switch outcome {
            case .opened:
                availability[item.id] = .available
                if env.preferences.closeAfterLaunch { controller?.hide() }
            case .completed(let message):
                showInfo(message)
                if env.preferences.closeAfterLaunch {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    controller?.hide()
                }
            case .unavailable(let state):
                availability[item.id] = state
                banner = Banner(kind: .problem(item, state))
            case .failed(let message):
                banner = Banner(kind: .error(message))
            }
        }
    }

    func revealSelected() {
        guard let item = selectedItem else { return }
        reveal(item)
    }

    func reveal(_ item: LaunchItem) {
        if env.launcher.reveal(item) {
            controller?.hide()
        } else if item.target.fileReference != nil || item.kind == .application {
            let state = env.resolver.resolve(item.target).availability
            banner = Banner(kind: .problem(item, state == .available ? .missing : state))
        }
    }

    // MARK: Editing

    func editSelected() {
        if let item = selectedItem { edit(item) }
    }

    func edit(_ item: LaunchItem) {
        controller?.perform(reopenAfter: false) {
            env.windows.showEditor(for: item)
            return nil
        }
    }

    func toggleFavoriteSelected() {
        if let item = selectedItem { env.library.togglePinned(item.id) }
    }

    func remove(_ item: LaunchItem) {
        env.library.remove(item.id)
        if banner.map({ if case .problem(let problem, _) = $0.kind { return problem.id == item.id }; return false }) == true {
            banner = nil
        }
        showInfo("Removed “\(item.name)”")
    }

    func relocate(_ item: LaunchItem) {
        banner = nil
        controller?.perform(reopenAfter: true) {
            env.adder.relocate(item)
        }
    }

    // MARK: Adding

    func addApplications() {
        controller?.perform(reopenAfter: true) { env.adder.chooseApplications(categoryID: categoryID)?.message }
    }

    func addFilesAndFolders() {
        controller?.perform(reopenAfter: true) { env.adder.chooseFilesAndFolders(categoryID: categoryID)?.message }
    }

    func addWebsite() {
        controller?.perform(reopenAfter: false) { env.windows.showNewItemEditor(kind: .website); return nil }
    }

    func addAction() {
        controller?.perform(reopenAfter: false) { env.windows.showNewItemEditor(kind: .action); return nil }
    }

    /// Handles files dropped onto the launcher from Finder, or links dragged from a browser.
    func handleDrop(fileURLs: [URL], webURLs: [URL]) {
        var summary = env.adder.add(urls: fileURLs, categoryID: categoryID)
        for url in webURLs {
            guard let item = try? env.factory.makeWebsite(address: url.absoluteString) else {
                summary.failures.append("Only web links (http or https) can be added as websites.")
                continue
            }
            var categorized = item
            categorized.categoryID = categoryID
            switch env.library.add(categorized) {
            case .added(let added): summary.added.append(added)
            case .duplicate(let existing): summary.duplicates.append(existing)
            }
        }
        let message = summary.message
        if !message.isEmpty { showInfo(message) }
        refreshAvailability()
    }

    // MARK: Reordering

    func moveDragged(onto target: LaunchItem) {
        guard canReorder, let draggingID, draggingID != target.id else { return }
        env.library.move(draggingID, to: target.id)
    }

    // MARK: Banners

    func showInfo(_ message: String) {
        banner = Banner(kind: .info(message))
    }

    private func scheduleBannerDismissal() {
        bannerTask?.cancel()
        guard let banner, case .info = banner.kind else { return }
        let id = banner.id
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, self.banner?.id == id else { return }
            self.banner = nil
        }
    }
}
