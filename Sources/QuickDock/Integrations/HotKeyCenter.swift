import AppKit
import Carbon.HIToolbox
import Combine
import QuickDockCore

/// Registers QuickDock's single global shortcut with Carbon's `RegisterEventHotKey`.
///
/// `RegisterEventHotKey` needs no Accessibility or Input Monitoring permission,
/// which is why it is used instead of an event tap.
@MainActor
final class HotKeyCenter: ObservableObject {
    enum Status: Equatable {
        case disabled
        case registered(KeyCombo)
        case failed(KeyCombo, message: String)
    }

    @Published private(set) var status: Status = .disabled

    /// Called on the main thread when the shortcut is pressed.
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isSuspended = false
    fileprivate static let signature: OSType = 0x5144_4B31 // "QDK1"

    var currentCombo: KeyCombo? {
        switch status {
        case .registered(let combo): return combo
        case .failed(let combo, _): return combo
        case .disabled: return nil
        }
    }

    var isRegistered: Bool {
        if case .registered = status { return true }
        return false
    }

    /// Registers `combo`, replacing any previous registration. Pass `nil` to disable.
    @discardableResult
    func register(_ combo: KeyCombo?) -> Bool {
        unregisterCurrent()
        guard let combo else {
            status = .disabled
            return true
        }
        if case .invalid(let message) = combo.validate() {
            status = .failed(combo, message: message)
            return false
        }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(combo.keyCode, combo.modifiers.carbonFlags,
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        if result == noErr, let ref {
            hotKeyRef = ref
            status = .registered(combo)
            return true
        }
        status = .failed(combo, message: Self.message(for: result, combo: combo))
        return false
    }

    /// Tries `combo`; if it can't be registered, restores the previous shortcut.
    /// Returns an error message on failure.
    func tryReplacing(with combo: KeyCombo?) -> String? {
        let previous = currentCombo
        let wasRegistered = isRegistered
        if register(combo) { return nil }
        let message: String
        if case .failed(_, let failure) = status { message = failure } else { message = "The shortcut couldn’t be registered." }
        if wasRegistered { register(previous) } else { status = previous.map { .failed($0, message: message) } ?? .disabled }
        return message
    }

    /// Temporarily releases the shortcut (while the user records a new one).
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        if case .registered(let combo) = status { register(combo) }
    }

    /// Releases the shortcut and the event handler (called on quit).
    func tearDown() {
        unregisterCurrent()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterCurrent() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr, hotKeyID.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.onPressed?() }
            }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }

    private static func message(for status: OSStatus, combo: KeyCombo) -> String {
        switch Int(status) {
        case eventHotKeyExistsErr:
            return "\(combo.displayString) is already used by another app. Choose a different shortcut."
        case eventHotKeyInvalidErr:
            return "macOS doesn’t allow \(combo.displayString) as a global shortcut. Choose a different shortcut."
        default:
            return "macOS couldn’t register \(combo.displayString) (error \(status)). Choose a different shortcut."
        }
    }
}

/// Layout-aware key names for display (e.g. "Z" vs "Y" on a German keyboard).
enum KeyboardLayout {
    static func name(for keyCode: UInt32) -> String {
        let special = KeyCodes.name(for: keyCode)
        // Named keys (Space, arrows, F-keys…) don't depend on the layout.
        if special.count > 1 || KeyCodes.functionKeyCodes.contains(keyCode) { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return special
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let result = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
        }
        guard result == noErr, length > 0 else { return special }
        let text = String(utf16CodeUnits: characters, count: length).uppercased()
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? special : text
    }

    static func displayString(for combo: KeyCombo) -> String {
        combo.displayString(keyName: name(for: combo.keyCode))
    }
}
