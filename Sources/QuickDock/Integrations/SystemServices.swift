import AppKit
import ServiceManagement
import QuickDockCore

/// Finds installed applications through Launch Services.
struct WorkspaceApplications: ApplicationLocating {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

/// Optional "Open at Login" using `SMAppService` (macOS 13+). No helper app is needed.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)
    }

    @Published private(set) var state: State = .disabled
    @Published var lastError: String?

    init() { refresh() }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notRegistered: state = .disabled
        case .notFound: state = .disabled
        @unknown default: state = .disabled
        }
    }

    var isEnabled: Bool { state == .enabled || state == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = enabled
                ? "QuickDock couldn’t be added to your login items. \(error.localizedDescription) Move QuickDock to the Applications folder and try again."
                : "QuickDock couldn’t be removed from your login items. \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// App metadata from Info.plist.
enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "io.github.quickdock.QuickDock" }

    /// Optional links configured at build time (see `config/release.env`). Empty values are hidden.
    static var websiteURL: URL? { configuredURL("QDWebsiteURL") }
    static var repositoryURL: URL? { configuredURL("QDRepositoryURL") }
    static var donationURL: URL? { configuredURL("QDDonationURL") }
    static var supportEmail: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "QDSupportEmail") as? String,
              PredefinedAction.isPlausibleEmail(value) else { return nil }
        return value
    }

    static var isSandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    private static func configuredURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              value.hasPrefix("https://"), let url = URL(string: value) else { return nil }
        return url
    }
}

extension NSApplication {
    /// Brings QuickDock's windows forward. QuickDock is a menu-bar (agent) app, so it
    /// only activates when the user opens one of its windows.
    func activateQuickDock() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
