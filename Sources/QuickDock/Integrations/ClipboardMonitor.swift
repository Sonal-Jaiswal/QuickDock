import AppKit
import Combine
import QuickDockCore

/// Opt-in clipboard history for text.
///
/// Privacy:
///  • Off until the user turns it on. macOS (15.4+) may then ask once whether QuickDock may
///    read the clipboard; the user can change this in System Settings › Privacy & Security.
///  • Only the change counter is polled; content is read only after it changes.
///  • Copies marked concealed/transient (password managers) are never recorded.
///  • History lives in memory unless "Remember after quitting" is on.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var history: ClipboardHistory
    @Published private(set) var isRunning = false

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let preferences: AppPreferences
    private var timer: Timer?
    private var lastChangeCount: Int
    private var cancellables = Set<AnyCancellable>()
    private var saveScheduled = false

    init(preferences: AppPreferences, store: ClipboardStore, pasteboard: NSPasteboard = .general) {
        self.preferences = preferences
        self.store = store
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        history = (preferences.clipboardRemember ? store.load() : nil) ?? ClipboardHistory(limit: preferences.clipboardLimit)
        history.limit = preferences.clipboardLimit

        preferences.$clipboardHistoryEnabled
            .sink { [weak self] enabled in
                DispatchQueue.main.async { enabled ? self?.start() : self?.stop() }
            }
            .store(in: &cancellables)
        preferences.$clipboardLimit
            .dropFirst()
            .sink { [weak self] limit in self?.history.limit = limit; self?.persist() }
            .store(in: &cancellables)
        preferences.$clipboardRemember
            .dropFirst()
            .sink { [weak self] remember in
                guard let self else { return }
                if remember { self.persist(force: true) } else { self.store.delete() }
            }
            .store(in: &cancellables)
    }

    /// The system's clipboard-access setting for QuickDock, when macOS reports one.
    var accessDescription: String? {
        guard #available(macOS 15.4, *) else { return nil }
        switch pasteboard.accessBehavior {
        case .alwaysDeny:
            return "macOS is blocking QuickDock from reading the clipboard. Allow it for QuickDock in System Settings › Privacy & Security."
        case .ask:
            return "macOS will ask before QuickDock reads the clipboard. Choose “Always Allow” in System Settings › Privacy & Security to stop the prompts."
        case .alwaysAllow, .default:
            return nil
        @unknown default:
            return nil
        }
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount // don't import whatever was copied before enabling
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Checks for a new copy now (also used by tests).
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !ClipboardHistory.shouldIgnore(pasteboardTypes: types),
              let text = pasteboard.string(forType: .string) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        if history.record(text, sourceApp: source == "QuickDock" ? nil : source) { persist() }
    }

    /// Puts an entry back on the clipboard (it then moves to the top of the history).
    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        history.record(entry.text, sourceApp: entry.sourceApp)
        lastChangeCount = pasteboard.changeCount
        persist()
    }

    func togglePin(_ id: UUID) { history.togglePin(id); persist() }
    func remove(_ id: UUID) { history.remove(id); persist() }
    func clear() { history.clearUnpinned(); persist() }

    func eraseAll() {
        history.removeAll()
        store.delete()
    }

    /// Records text directly (used by the debug QA harness to stage screenshots).
    func recordForTesting(_ text: String, source: String?) { history.record(text, sourceApp: source) }

    func flush() { persist(force: true) }

    private func persist(force: Bool = false) {
        guard preferences.clipboardRemember else { return }
        if force { try? store.save(history); return }
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            try? self.store.save(self.history)
        }
    }
}
