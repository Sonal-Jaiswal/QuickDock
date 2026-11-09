import AppKit
import SwiftUI
import QuickDockCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, launcher, shortcuts, wheel, organization, data, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .launcher: return "Launcher"
        case .shortcuts: return "Shortcuts"
        case .wheel: return "Wheel & Clipboard"
        case .organization: return "Organization"
        case .data: return "Data"
        case .about: return "About QuickDock"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .launcher: return "square.grid.3x3"
        case .shortcuts: return "keyboard"
        case .wheel: return "circle.grid.cross"
        case .organization: return "folder"
        case .data: return "externaldrive"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var section: SettingsSection = .general
}

struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: Binding(
                get: { Optional(selection.section) },
                set: { if let value = $0 { selection.section = value } }
            )) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection.section {
                case .general: GeneralSettings()
                case .appearance: AppearanceSettings()
                case .launcher: LauncherSettings()
                case .shortcuts: ShortcutSettings()
                case .wheel: WheelSettings()
                case .organization: OrganizationSettings()
                case .data: DataSettings()
                case .about: AboutSettings()
                }
            }
            .navigationTitle(selection.section.title)
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var loginItem: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                Toggle("Open QuickDock at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.state == .requiresApproval {
                    HStack {
                        Label("Waiting for your approval in System Settings › General › Login Items.", systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { loginItem.openLoginItemsSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } footer: {
                Text("QuickDock starts quietly in the menu bar.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Close the launcher after opening an item", isOn: $preferences.closeAfterLaunch)
                Toggle("Show favorites in the menu-bar menu", isOn: $preferences.showFavoritesInMenu)
            }

            Section("Using QuickDock") {
                HelpRow(symbol: "cursorarrow.click", text: "Click the QuickDock icon in the menu bar to open or close the launcher. Right-click it for more options.")
                HelpRow(symbol: "keyboard", text: "Press your global shortcut from any app. Change it under Keyboard Shortcuts.")
                HelpRow(symbol: "hand.draw", text: "Drag apps, files, folders or links onto the launcher to add them. Drag tiles to reorder.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}

struct HelpRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    ForEach(AppearanceMode.allCases) { mode in
                        AppearanceChoice(mode: mode, isSelected: preferences.appearance == mode) {
                            preferences.appearance = mode
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your Mac’s Light or Dark setting.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show item names", isOn: $preferences.showLabels)
                Picker("Icon size", selection: $preferences.iconSize) {
                    ForEach(IconSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Launcher

private struct LauncherSettings: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Grid") {
                Stepper(value: $preferences.gridColumns, in: AppPreferences.columnRange) {
                    LabeledContent("Columns", value: "\(preferences.gridColumns)")
                }
                Stepper(value: $preferences.maxVisibleRows, in: AppPreferences.rowRange) {
                    LabeledContent("Visible rows", value: "\(preferences.maxVisibleRows)")
                }
                Picker("Icon size", selection: $preferences.iconSize) {
                    ForEach(IconSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show item names", isOn: $preferences.showLabels)
                LabeledContent("Launcher size") {
                    let size = LauncherMetrics(preferences: preferences).panelSize
                    Text("\(Int(size.width)) × \(Int(size.height)) points").foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("When the launcher opens, show", selection: $preferences.startFilter) {
                    ForEach(LauncherStartFilter.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("The launcher opens centred on the display containing the pointer. If it doesn’t fit, the grid scrolls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Show Launcher") { env.launcherController?.show() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @EnvironmentObject private var hotKeys: HotKeyCenter
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                LabeledContent("Open QuickDock") {
                    ShortcutRecorder(hotKeys: hotKeys, combo: $preferences.hotKey, otherCombo: preferences.wheelHotKey, otherPurpose: "the Quick Wheel")
                }
                statusRow
            } header: {
                Text("Global shortcut")
            } footer: {
                Text("Works from any app. QuickDock uses the standard macOS hot-key service, which needs no Accessibility or Input Monitoring permission. Note: a shortcut such as ⌥Space replaces the character it would normally type.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("In the launcher") {
                ShortcutRow(keys: "↑ ↓ ← →", action: "Move the selection")
                ShortcutRow(keys: "↩", action: "Open the selected item")
                ShortcutRow(keys: "⌘↩", action: "Show the selected item in Finder")
                ShortcutRow(keys: "⌘1 – ⌘9", action: "Open the first nine items")
                ShortcutRow(keys: "⇥  ⇧⇥", action: "Next / previous filter")
                ShortcutRow(keys: "⌘E", action: "Edit the selected item")
                ShortcutRow(keys: "⌘D", action: "Add to or remove from Favorites")
                ShortcutRow(keys: "⌘,", action: "Open Settings")
                ShortcutRow(keys: "⎋", action: "Clear the search, then close")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch hotKeys.status {
        case .registered(let combo):
            Label("\(KeyboardLayout.displayString(for: combo)) is active.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .disabled:
            Label("The global shortcut is off. Use the menu-bar icon to open QuickDock.", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String
    var body: some View {
        LabeledContent(action) { Keycap(text: keys) }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                VStack(spacing: 4) {
                    Text("QuickDock").font(.system(size: 24, weight: .semibold))
                    Text("Your Mac, one click away.").foregroundStyle(.secondary)
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Private by design", systemImage: "lock.shield").font(.headline)
                        Text("QuickDock keeps everything on this Mac. It has no account, no cloud sync, no analytics and no ads, and it never connects to the internet.")
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Label("Early access build", systemImage: "exclamationmark.shield").font(.headline)
                        Text("This version is not signed with an Apple Developer ID and has not been notarized by Apple. macOS may warn you before opening it. Only install QuickDock from its official GitHub Releases page.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(maxWidth: 460)

                HStack(spacing: 16) {
                    if let url = AppInfo.websiteURL { Link("Website", destination: url) }
                    if let url = AppInfo.repositoryURL {
                        Link("Source Code", destination: url)
                        Link("Release Notes", destination: url.appendingPathComponent("releases"))
                        Link("Report an Issue", destination: url.appendingPathComponent("issues"))
                    }
                    if let email = AppInfo.supportEmail, let url = PredefinedAction.mailtoURL(recipient: email) {
                        Link("Contact", destination: url)
                    }
                }
                .font(.callout)

                if let url = AppInfo.donationURL {
                    Link(destination: url) {
                        Label("Support QuickDock", systemImage: "heart.fill")
                    }
                    .font(.callout.weight(.medium))
                    .help("Optional donations help pay for Apple code signing")
                }

                Text("Released under the MIT License. © 2026 The QuickDock Authors.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
    }
}
