import Foundation

/// Built-in actions QuickDock can perform.
///
/// Every action is implemented with public, sandbox-friendly APIs: opening a
/// system application or a system URL, or writing to the pasteboard.
/// QuickDock never runs shell commands or scripts. User text is only ever used
/// as pasteboard content or as an e-mail address in a `mailto:` URL.
public enum PredefinedAction: String, Codable, CaseIterable, Sendable {
    case copySnippet
    case composeEmail
    case startScreenSaver
    case takeScreenshot
    case missionControl
    case systemSettings
    case quickDockSettings

    public var title: String {
        switch self {
        case .copySnippet: return "Copy Text Snippet"
        case .composeEmail: return "New Email"
        case .startScreenSaver: return "Start Screen Saver"
        case .takeScreenshot: return "Take Screenshot"
        case .missionControl: return "Mission Control"
        case .systemSettings: return "System Settings"
        case .quickDockSettings: return "QuickDock Settings"
        }
    }

    public var subtitle: String {
        switch self {
        case .copySnippet: return "Copies saved text to the clipboard"
        case .composeEmail: return "Starts a new message in your mail app"
        case .startScreenSaver: return "Starts the screen saver immediately"
        case .takeScreenshot: return "Opens the macOS Screenshot tool"
        case .missionControl: return "Shows all open windows and spaces"
        case .systemSettings: return "Opens System Settings"
        case .quickDockSettings: return "Opens QuickDock's settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .copySnippet: return "doc.on.clipboard"
        case .composeEmail: return "envelope"
        case .startScreenSaver: return "sparkles.tv"
        case .takeScreenshot: return "camera.viewfinder"
        case .missionControl: return "rectangle.3.group"
        case .systemSettings: return "gearshape"
        case .quickDockSettings: return "slider.horizontal.3"
        }
    }

    /// Whether the action needs user-provided text.
    public var requiresText: Bool {
        switch self {
        case .copySnippet: return true
        case .composeEmail: return false // recipient is optional
        default: return false
        }
    }

    /// Whether the action accepts optional text.
    public var acceptsText: Bool {
        self == .copySnippet || self == .composeEmail
    }

    public var textFieldLabel: String {
        switch self {
        case .copySnippet: return "Snippet text"
        case .composeEmail: return "Recipient (optional)"
        default: return ""
        }
    }

    /// Bundle identifier of the system app that performs this action, if any.
    public var systemAppBundleIdentifier: String? {
        switch self {
        case .startScreenSaver: return "com.apple.ScreenSaver.Engine"
        case .takeScreenshot: return "com.apple.screenshot.launcher"
        case .missionControl: return "com.apple.exposelauncher"
        case .systemSettings: return "com.apple.systempreferences"
        default: return nil
        }
    }

    /// Well-known locations used when Launch Services cannot find the bundle identifier.
    public var systemAppFallbackPaths: [String] {
        switch self {
        case .startScreenSaver: return ["/System/Library/CoreServices/ScreenSaverEngine.app"]
        case .takeScreenshot: return ["/System/Applications/Utilities/Screenshot.app"]
        case .missionControl: return ["/System/Applications/Mission Control.app"]
        case .systemSettings: return ["/System/Applications/System Settings.app",
                                      "/System/Applications/System Preferences.app"]
        default: return []
        }
    }

    /// Maximum length of snippet text (keeps imported configurations sane).
    public static let maximumTextLength = 10_000

    /// Builds the `mailto:` URL for `composeEmail`. Returns `nil` when the
    /// recipient is not a plausible e-mail address.
    public static func mailtoURL(recipient: String?) -> URL? {
        let trimmed = (recipient ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return URL(string: "mailto:") }
        guard isPlausibleEmail(trimmed) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = trimmed
        return components.url
    }

    public static func isPlausibleEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?&,;<>\"'()[]\\"))
        return value.rangeOfCharacter(from: forbidden) == nil
    }
}
