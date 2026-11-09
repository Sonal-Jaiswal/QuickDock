import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickDockCore

/// Export, import, access recovery and resets.
struct DataSettings: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var preferences: AppPreferences
    @State private var status: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Export Configuration") {
                    Button("Export…", action: exportConfiguration)
                }
                LabeledContent("Import Configuration") {
                    Button("Import…", action: importConfiguration)
                }
            } header: {
                Text("Backup and transfer")
            } footer: {
                Text("A configuration file contains your items, categories, custom icons and settings. File access permissions can’t be exported, so imported files and folders ask you to locate them once.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Restore File Access") {
                    Button("Choose Folder…", action: restoreAccess)
                }
            } footer: {
                Text("If several files show “Needs access” (for example after importing, or after updating QuickDock), choose a folder that contains them — such as your Home folder — to restore access in one step.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let status {
                Section {
                    Label(status, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                LabeledContent("Data folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([library.store.fileURL])
                    }
                }
                if let error = library.saveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Items are saved in library.json with an automatic backup of the previous version. Nothing leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reset") {
                LabeledContent("Preferences") {
                    Button("Reset Preferences…", action: resetPreferences)
                }
                LabeledContent("Items and categories") {
                    Button("Remove All Items…", role: .destructive, action: removeAllItems)
                        .disabled(library.items.isEmpty && library.categories.isEmpty)
                }
                LabeledContent("Welcome screens") {
                    Button("Show Welcome Again") { env.windows.showOnboarding() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func report(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = "Export QuickDock Configuration"
        panel.nameFieldStringValue = "QuickDock Configuration.\(ConfigurationDocument.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: ConfigurationDocument.fileExtension) ?? .json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            library.flush()
            let data = try ConfigurationTransfer.export(snapshot: library.snapshot, preferences: preferences.snapshot,
                                                        iconStore: env.iconStore, appVersion: AppInfo.version)
            try data.write(to: url, options: .atomic)
            report("Exported \(library.items.count) item\(library.items.count == 1 ? "" : "s") to “\(url.lastPathComponent)”.")
        } catch {
            report("Export failed. \(error.localizedDescription)", error: true)
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Import QuickDock Configuration"
        panel.allowedContentTypes = [UTType(filenameExtension: ConfigurationDocument.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let plan: ImportPlan
        do {
            let data = try SecurityScope.access(url) { try Data(contentsOf: url, options: .mappedIfSafe) }
            plan = try ConfigurationTransfer.parse(data)
        } catch {
            report(error.localizedDescription, error: true)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import \(plan.items.count) item\(plan.items.count == 1 ? "" : "s")?"
        var info = "Merge adds new items to your current ones. Replace removes your current items first."
        if plan.preferences != nil { info += " Settings from the file will also be applied." }
        if plan.fileItemCount > 0 { info += " You’ll need to locate \(plan.fileItemCount) file or folder item\(plan.fileItemCount == 1 ? "" : "s") once to grant access." }
        if !plan.warnings.isEmpty { info += "\n\n" + plan.warnings.joined(separator: "\n") }
        alert.informativeText = info
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        let choice = alert.runModal()
        guard choice != .alertThirdButtonReturn else { return }

        // Store embedded icons first so items reference real files.
        var items = plan.items
        for index in items.indices {
            if let png = plan.iconImages[items[index].id], let name = try? env.iconStore.storeImageData(png) {
                items[index].customIcon = .image(fileName: name)
            }
        }
        if choice == .alertFirstButtonReturn {
            let result = library.merge(items: items, categories: plan.categories)
            report("Imported \(result.added) item\(result.added == 1 ? "" : "s")" + (result.skipped > 0 ? "; \(result.skipped) already existed." : "."))
        } else {
            library.replaceAll(with: LibrarySnapshot(items: items, categories: plan.categories))
            report("Replaced your items with \(items.count) imported item\(items.count == 1 ? "" : "s").")
        }
        if let prefs = plan.preferences {
            let previousHotKey = preferences.hotKey
            preferences.apply(prefs)
            if preferences.hotKey != previousHotKey, let error = env.hotKeys.tryReplacing(with: preferences.hotKey) {
                preferences.hotKey = previousHotKey
                report((status ?? "") + " The imported shortcut couldn’t be used: \(error)", error: true)
            }
        }
        env.launcherController?.model.refreshAvailability()
    }

    private func restoreAccess() {
        guard let count = env.adder.restoreAccess() else { return }
        report(count == 0 ? "No QuickDock items were found in that folder."
               : "Restored access to \(count) item\(count == 1 ? "" : "s").", error: count == 0)
        env.launcherController?.model.refreshAvailability()
    }

    private func resetPreferences() {
        let alert = NSAlert()
        alert.messageText = "Reset all preferences?"
        alert.informativeText = "Appearance, grid layout, launcher behaviour and the keyboard shortcut return to their defaults. Your items aren’t affected."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        preferences.resetToDefaults()
        if let error = env.hotKeys.tryReplacing(with: preferences.hotKey) {
            report("Preferences were reset, but the default shortcut couldn’t be registered: \(error)", error: true)
        } else {
            report("Preferences were reset.")
        }
    }

    private func removeAllItems() {
        let alert = NSAlert()
        alert.messageText = "Remove all items and categories?"
        alert.informativeText = "This empties QuickDock. Your apps, files and folders aren’t touched. Consider exporting a configuration first — this can’t be undone."
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        library.removeEverything()
        report("All items were removed.")
    }
}
