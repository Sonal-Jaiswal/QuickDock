import AppKit
import SwiftUI
import QuickDockCore

/// A key-cap style label for shortcuts, e.g. ⌥ Space.
struct Keycap: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.system(size: prominent ? 15 : 11, weight: .medium, design: .rounded))
            .padding(.horizontal, prominent ? 12 : 6)
            .padding(.vertical, prominent ? 6 : 2)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: prominent ? 8 : 5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: prominent ? 8 : 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .accessibilityLabel(text)
    }
}

/// A plain search field (AppKit) that QuickDock can focus programmatically.
/// Navigation keys are handled by `LauncherController`.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 21, weight: .regular)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Search QuickDock")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var lastFocusToken = -1
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// Records a new global shortcut. While recording, the current shortcut is
/// suspended so it can be pressed again.
struct ShortcutRecorder: View {
    @ObservedObject var hotKeys: HotKeyCenter
    /// The stored shortcut this recorder edits.
    @Binding var combo: KeyCombo?
    var defaultCombo: KeyCombo = .defaultLauncher
    /// Another QuickDock shortcut this one must not duplicate, with its purpose.
    var otherCombo: KeyCombo? = nil
    var otherPurpose: String = ""
    @State private var isRecording = false
    @State private var message: String?
    @State private var isWarning = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: toggleRecording) {
                    HStack(spacing: 6) {
                        if isRecording {
                            Image(systemName: "record.circle").foregroundStyle(.red)
                            Text("Type shortcut…")
                        } else if let combo {
                            Text(KeyboardLayout.displayString(for: combo))
                                .font(.system(.body, design: .rounded).weight(.medium))
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 120)
                }
                .help(isRecording ? "Press the new shortcut, or Escape to cancel" : "Click to record a new shortcut")

                if isRecording {
                    Button("Cancel") { stopRecording() }
                } else {
                    if combo != defaultCombo {
                        Button("Use \(KeyboardLayout.displayString(for: defaultCombo))") { apply(defaultCombo) }
                    }
                    if combo != nil {
                        Button("Turn Off") { apply(nil) }
                    }
                }
            }
            if let message {
                Label(message, systemImage: isWarning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(isWarning ? Color.orange : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        message = nil
        isRecording = true
        hotKeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == UInt16(KeyCodes.escape) && flags.isEmpty {
                stopRecording()
                return nil
            }
            var modifiers: KeyCombo.Modifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            switch combo.validate() {
            case .invalid(let reason):
                message = reason
                isWarning = false
                NSSound.beep()
            case .warning(let reason):
                stopRecording()
                apply(combo)
                if message == nil { message = reason; isWarning = true }
            case .valid:
                stopRecording()
                apply(combo)
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            hotKeys.resume()
        }
    }

    private func apply(_ newCombo: KeyCombo?) {
        if let newCombo, newCombo == otherCombo {
            message = "\(KeyboardLayout.displayString(for: newCombo)) is already QuickDock’s shortcut for \(otherPurpose)."
            isWarning = false
            return
        }
        let combo = newCombo
        if let error = hotKeys.tryReplacing(with: combo) {
            message = error
            isWarning = false
        } else {
            self.combo = combo
            message = nil
        }
    }
}

/// A rounded card used for appearance selection in Settings and onboarding.
struct AppearanceChoice: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearanceThumbnail(mode: mode)
                    .frame(width: 112, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                    )
                Text(mode.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AppearanceThumbnail: View {
    let mode: AppearanceMode

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch mode {
                case .light: panel(dark: false)
                case .dark: panel(dark: true)
                case .system:
                    HStack(spacing: 0) {
                        panel(dark: false).frame(width: proxy.size.width / 2).clipped()
                        panel(dark: true).frame(width: proxy.size.width / 2).clipped()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func panel(dark: Bool) -> some View {
        ZStack {
            (dark ? Color(white: 0.16) : Color(white: 0.93))
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10))
                    .frame(height: 8)
                HStack(spacing: 6) {
                    ForEach([IconTint.blue, .orange, .green, .purple], id: \.self) { tint in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.color).frame(width: 16, height: 16)
                    }
                }
            }
            .padding(10)
        }
    }
}
