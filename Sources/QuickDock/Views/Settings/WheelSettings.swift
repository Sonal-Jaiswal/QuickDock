import SwiftUI
import QuickDockCore

/// Settings for the Quick Wheel and clipboard history.
struct WheelSettings: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var clipboard: ClipboardMonitor

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(hotKeys: env.wheelHotKeys, combo: $preferences.wheelHotKey, defaultCombo: .defaultWheel,
                                     otherCombo: preferences.hotKey, otherPurpose: "opening the launcher")
                }
                wheelStatus
                Picker("Shows", selection: $preferences.wheelSource) {
                    ForEach(WheelSource.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $preferences.wheelSlots, in: WheelLayout.slotRange) {
                    LabeledContent("Slots", value: "\(preferences.wheelSlots)")
                }
                Toggle("Show clipboard next to the wheel", isOn: $preferences.showClipboardInWheel)
                Button("Show Quick Wheel") {
                    let frame = LauncherController.activeScreen().visibleFrame
                    env.wheelController?.show(at: NSPoint(x: frame.midX, y: frame.midY), holding: false)
                }
            } header: {
                Text("Quick Wheel")
            } footer: {
                Text("Hold the shortcut, move the pointer towards an app and let go to open it — or switch to it if it’s already running. Tap the shortcut to keep the wheel open and click instead. While still holding the modifier keys, press Tab again to step through the slots. Number keys 1–9 open a slot directly.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep clipboard history", isOn: $preferences.clipboardHistoryEnabled)
                if preferences.clipboardHistoryEnabled {
                    if let note = clipboard.accessDescription {
                        Label(note, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Remember history after quitting", isOn: $preferences.clipboardRemember)
                    Stepper(value: $preferences.clipboardLimit, in: ClipboardHistory.limitRange, step: 10) {
                        LabeledContent("Keep up to", value: "\(preferences.clipboardLimit) items")
                    }
                    LabeledContent("History") {
                        HStack {
                            Text("\(clipboard.history.entries.count) items").foregroundStyle(.secondary)
                            Button("Clear") { clipboard.clear() }
                            Button("Erase All", role: .destructive) { clipboard.eraseAll() }
                        }
                    }
                }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Only text is kept, only on this Mac, and never sent anywhere. Copies that password managers mark as private are skipped. Without “Remember”, history is cleared when QuickDock quits. Pinned items survive Clear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.clipboardHistoryEnabled) { enabled in
            if !enabled { clipboard.eraseAll() }
        }
    }

    @ViewBuilder
    private var wheelStatus: some View {
        switch env.wheelHotKeys.status {
        case .registered(let combo):
            Label("Hold \(KeyboardLayout.displayString(for: combo)) to open the wheel.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .disabled:
            Label("The wheel shortcut is off. Open the wheel from the menu-bar icon.", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}
