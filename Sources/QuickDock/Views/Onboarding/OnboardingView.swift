import AppKit
import SwiftUI
import QuickDockCore

/// The five-step first-launch experience. No permissions are requested.
struct OnboardingView: View {
    /// `true` opens the launcher after finishing.
    let finish: (Bool) -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var hotKeys: HotKeyCenter
    @State private var step = 0
    @State private var suggestions: [SuggestedApp] = []
    @State private var chosen = Set<String>()
    @State private var addedMessage: String?

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: explanation
                case 2: appearance
                case 3: firstItems
                default: shortcut
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .transition(.opacity)
            .id(step)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(stepCount)")
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                }
                primaryButton
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 680, height: 520)
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear(perform: loadSuggestions)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case 0:
            Button("Get Started") { withAnimation { step = 1 } }.keyboardShortcut(.defaultAction)
        case 3:
            Button(chosen.isEmpty ? "Skip" : "Add \(chosen.count) App\(chosen.count == 1 ? "" : "s")") {
                addChosen()
                withAnimation { step = 4 }
            }
            .keyboardShortcut(.defaultAction)
        case stepCount - 1:
            Button("Open QuickDock") { finish(true) }.keyboardShortcut(.defaultAction)
        default:
            Button("Continue") { withAnimation { step += 1 } }.keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            Text("Welcome to QuickDock")
                .font(.system(size: 30, weight: .semibold))
            Text("Your Mac, one click away.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Keep the apps, files, folders and websites you use every day in one beautiful launcher you can open from anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Spacer()
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepTitle(title: "How QuickDock works", subtitle: "A personal launcher — not a search engine.")
            FeatureRow(symbol: "square.grid.2x2", tint: .blue, title: "Your favourite things, together",
                       text: "Add applications, files, folders, websites and handy actions. QuickDock shows only what you choose.")
            FeatureRow(symbol: "keyboard", tint: .purple, title: "Open it from anywhere",
                       text: "Press your keyboard shortcut or click the QuickDock icon in the menu bar. It floats above your windows and gets out of the way when you’re done.")
            FeatureRow(symbol: "line.3.horizontal.decrease.circle", tint: .orange, title: "Stay organised",
                       text: "Search instantly, filter by type, mark favorites, group items into categories and drag tiles into your own order.")
            FeatureRow(symbol: "lock.shield", tint: .green, title: "Private by design",
                       text: "Everything stays on your Mac. No account, no tracking, no internet connection needed.")
            Spacer()
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepTitle(title: "Choose a look", subtitle: "You can change this any time in Settings.")
            HStack(spacing: 22) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceChoice(mode: mode, isSelected: preferences.appearance == mode) {
                        preferences.appearance = mode
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var firstItems: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: "Add your first items", subtitle: "Pick some apps to start with, or choose your own.")
            if suggestions.isEmpty {
                Text("Use the buttons below to choose apps, files or folders.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(suggestions) { app in
                        SuggestionChip(app: app, isOn: chosen.contains(app.bundleID)) {
                            if chosen.contains(app.bundleID) { chosen.remove(app.bundleID) } else { chosen.insert(app.bundleID) }
                        }
                    }
                }
            }
            HStack {
                Button("Choose Apps…") { addedMessage = env.adder.chooseApplications()?.message }
                Button("Choose Files or Folders…") { addedMessage = env.adder.chooseFilesAndFolders()?.message }
                Spacer()
                Text("\(library.items.count) item\(library.items.count == 1 ? "" : "s") in QuickDock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let addedMessage {
                Text(addedMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(title: "Open QuickDock anytime", subtitle: "Two ways, from any app.")
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Keyboard shortcut", systemImage: "keyboard").font(.headline)
                    if let combo = hotKeys.currentCombo, hotKeys.isRegistered {
                        Keycap(text: KeyboardLayout.displayString(for: combo), prominent: true)
                    }
                    ShortcutRecorder(hotKeys: hotKeys, preferences: preferences)
                    if case .failed(_, let message) = hotKeys.status {
                        Text(message).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

                VStack(alignment: .leading, spacing: 10) {
                    Label("Menu bar", systemImage: "menubar.rectangle").font(.headline)
                    HStack(spacing: 8) {
                        Image(nsImage: StatusItemController.makeIcon())
                            .renderingMode(.template)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                        Text("Click the QuickDock icon near the clock. Right-click it for Settings and Quit.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            }
            Text("Tip: drag apps, files or links onto the launcher to add more.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Suggestions

    struct SuggestedApp: Identifiable {
        let bundleID: String
        let name: String
        let url: URL
        var id: String { bundleID }
    }

    private static let candidates = [
        "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.Notes", "com.apple.finder",
        "com.apple.reminders", "com.apple.Music", "com.apple.Photos", "com.apple.MobileSMS", "com.apple.Terminal",
        "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.tinyspeck.slackmacgap",
        "com.spotify.client", "com.microsoft.teams2", "us.zoom.xos", "notion.id", "com.figma.Desktop",
    ]

    private func loadSuggestions() {
        guard suggestions.isEmpty else { return }
        let existing = Set(library.items.compactMap { item -> String? in
            if case .application(let app) = item.target { return app.bundleIdentifier }
            return nil
        })
        suggestions = Self.candidates.compactMap { bundleID in
            guard !existing.contains(bundleID),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
            return SuggestedApp(bundleID: bundleID, name: ItemFactory.stripAppExtension(name), url: url)
        }
        .prefix(12)
        .map { $0 }
    }

    private func addChosen() {
        let urls = suggestions.filter { chosen.contains($0.bundleID) }.map(\.url)
        guard !urls.isEmpty else { return }
        addedMessage = env.adder.add(urls: urls).message
        chosen.removeAll()
    }
}

private struct StepTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: IconTint
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SymbolTile(symbol: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SuggestionChip: View {
    let app: OnboardingView.SuggestedApp
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 28, height: 28)
                Text(app.name).lineLimit(1).font(.callout)
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isOn ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
