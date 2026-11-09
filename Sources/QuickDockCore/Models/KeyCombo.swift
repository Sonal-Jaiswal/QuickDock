import Foundation

/// A global keyboard shortcut: a virtual key code plus modifier keys.
///
/// Key codes are macOS virtual key codes (`kVK_*`), which identify physical keys.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        /// Carbon modifier mask used by `RegisterEventHotKey`.
        public var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.command) { flags |= 0x0100 } // cmdKey
            if contains(.shift) { flags |= 0x0200 } // shiftKey
            if contains(.option) { flags |= 0x0800 } // optionKey
            if contains(.control) { flags |= 0x1000 } // controlKey
            return flags
        }

        /// Symbols in Apple's canonical order: ⌃⌥⇧⌘.
        public var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Option + Space.
    public static let defaultLauncher = KeyCombo(keyCode: KeyCodes.space, modifiers: [.option])
    /// Used if Option + Space is already taken: Control + Option + Space.
    public static let fallbackLauncher = KeyCombo(keyCode: KeyCodes.space, modifiers: [.control, .option])

    /// Control + Option + Tab: hold to show the Quick Wheel, release to open the highlighted item.
    /// (Plain ⌥Tab is not delivered to apps by current macOS; see `validate()`.)
    public static let defaultWheel = KeyCombo(keyCode: KeyCodes.tab, modifiers: [.control, .option])

    /// A display string such as "⌥Space". `keyName` lets the app supply a
    /// layout-aware name for the key; it falls back to US-layout names.
    public func displayString(keyName: String? = nil) -> String {
        modifiers.symbols + (keyName ?? KeyCodes.name(for: keyCode))
    }

    public var displayString: String { displayString() }

    // MARK: Validation

    public enum Validation: Equatable, Sendable {
        case valid
        /// Allowed, but likely to clash with a macOS shortcut.
        case warning(String)
        /// Not allowed.
        case invalid(String)
    }

    public func validate() -> Validation {
        if KeyCodes.modifierKeyCodes.contains(keyCode) {
            return .invalid("Press a key together with the modifier keys.")
        }
        let isFunctionKey = KeyCodes.functionKeyCodes.contains(keyCode)
        let primary: Modifiers = [.command, .option, .control]
        if modifiers.intersection(primary).isEmpty && !isFunctionKey {
            return .invalid("Use at least one of ⌘ Command, ⌥ Option or ⌃ Control.")
        }
        if keyCode == KeyCodes.escape || keyCode == KeyCodes.tab && modifiers.contains(.command) {
            return .invalid("\(displayString) is reserved by macOS.")
        }
        // Registering ⌥Tab (or ⌥⇧Tab) succeeds, but current macOS never delivers the key press;
        // it goes to the frontmost app instead. Seen on macOS 27, where ⌥Space still works.
        if keyCode == KeyCodes.tab && modifiers.subtracting(.shift) == .option {
            return .invalid("macOS doesn’t pass \(displayString) to apps. Add ⌃ Control, for example ⌃⌥Tab.")
        }
        // ⌘ or ⌘⇧ with a letter, digit or punctuation would override everyday app shortcuts (⌘Q, ⌘C…).
        if modifiers.subtracting(.shift) == .command && !isFunctionKey && keyCode != KeyCodes.space {
            return .invalid("\(displayString) would override shortcuts in other apps. Add ⌥ Option or ⌃ Control.")
        }
        if let conflict = KeyCombo.knownSystemShortcuts[self] {
            return .warning("\(displayString) is normally used for \(conflict). It may not work reliably.")
        }
        return .valid
    }

    /// Shortcuts macOS reserves by default. Carbon cannot detect these conflicts,
    /// so QuickDock warns about them up front.
    public static let knownSystemShortcuts: [KeyCombo: String] = [
        KeyCombo(keyCode: KeyCodes.space, modifiers: [.command]): "Spotlight",
        KeyCombo(keyCode: KeyCodes.space, modifiers: [.command, .option]): "Finder search",
        KeyCombo(keyCode: KeyCodes.space, modifiers: [.control]): "switching input sources",
        KeyCombo(keyCode: KeyCodes.space, modifiers: [.control, .option]): "switching input sources (on some Macs)",
        KeyCombo(keyCode: KeyCodes.space, modifiers: [.control, .command]): "the Emoji & Symbols viewer",
        KeyCombo(keyCode: KeyCodes.upArrow, modifiers: [.control]): "Mission Control",
        KeyCombo(keyCode: KeyCodes.downArrow, modifiers: [.control]): "App Exposé",
        KeyCombo(keyCode: KeyCodes.leftArrow, modifiers: [.control]): "switching Spaces",
        KeyCombo(keyCode: KeyCodes.rightArrow, modifiers: [.control]): "switching Spaces",
        KeyCombo(keyCode: KeyCodes.q, modifiers: [.control, .command]): "locking the screen",
        KeyCombo(keyCode: KeyCodes.three, modifiers: [.command, .shift]): "screenshots",
        KeyCombo(keyCode: KeyCodes.four, modifiers: [.command, .shift]): "screenshots",
        KeyCombo(keyCode: KeyCodes.five, modifiers: [.command, .shift]): "the Screenshot tool",
        KeyCombo(keyCode: KeyCodes.d, modifiers: [.command, .option]): "showing or hiding the Dock",
        KeyCombo(keyCode: KeyCodes.escape, modifiers: [.command, .option]): "Force Quit",
    ]
}

/// macOS virtual key codes (from Carbon's `Events.h`, ANSI layout).
public enum KeyCodes {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03
    public static let h: UInt32 = 0x04, g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07
    public static let c: UInt32 = 0x08, v: UInt32 = 0x09, b: UInt32 = 0x0B, q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F, y: UInt32 = 0x10
    public static let t: UInt32 = 0x11, one: UInt32 = 0x12, two: UInt32 = 0x13, three: UInt32 = 0x14
    public static let four: UInt32 = 0x15, six: UInt32 = 0x16, five: UInt32 = 0x17, equal: UInt32 = 0x18
    public static let nine: UInt32 = 0x19, seven: UInt32 = 0x1A, minus: UInt32 = 0x1B, eight: UInt32 = 0x1C
    public static let zero: UInt32 = 0x1D, rightBracket: UInt32 = 0x1E, o: UInt32 = 0x1F, u: UInt32 = 0x20
    public static let leftBracket: UInt32 = 0x21, i: UInt32 = 0x22, p: UInt32 = 0x23, returnKey: UInt32 = 0x24
    public static let l: UInt32 = 0x25, j: UInt32 = 0x26, quote: UInt32 = 0x27, k: UInt32 = 0x28
    public static let semicolon: UInt32 = 0x29, backslash: UInt32 = 0x2A, comma: UInt32 = 0x2B, slash: UInt32 = 0x2C
    public static let n: UInt32 = 0x2D, m: UInt32 = 0x2E, period: UInt32 = 0x2F, tab: UInt32 = 0x30
    public static let space: UInt32 = 0x31, grave: UInt32 = 0x32, delete: UInt32 = 0x33, escape: UInt32 = 0x35
    public static let leftArrow: UInt32 = 0x7B, rightArrow: UInt32 = 0x7C, downArrow: UInt32 = 0x7D, upArrow: UInt32 = 0x7E
    public static let forwardDelete: UInt32 = 0x75, home: UInt32 = 0x73, end: UInt32 = 0x77
    public static let pageUp: UInt32 = 0x74, pageDown: UInt32 = 0x79

    public static let functionKeys: [(code: UInt32, name: String)] = [
        (0x7A, "F1"), (0x78, "F2"), (0x63, "F3"), (0x76, "F4"), (0x60, "F5"), (0x61, "F6"),
        (0x62, "F7"), (0x64, "F8"), (0x65, "F9"), (0x6D, "F10"), (0x67, "F11"), (0x6F, "F12"),
        (0x69, "F13"), (0x6B, "F14"), (0x71, "F15"), (0x6A, "F16"), (0x40, "F17"), (0x4F, "F18"),
        (0x50, "F19"), (0x5A, "F20"),
    ]
    public static let functionKeyCodes = Set(functionKeys.map(\.code))

    /// Command, Shift, Caps Lock, Option, Control (left/right), Fn.
    public static let modifierKeyCodes: Set<UInt32> = [0x37, 0x36, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]

    private static let names: [UInt32: String] = {
        var map: [UInt32: String] = [
            a: "A", s: "S", d: "D", f: "F", h: "H", g: "G", z: "Z", x: "X", c: "C", v: "V", b: "B", q: "Q",
            w: "W", e: "E", r: "R", y: "Y", t: "T", one: "1", two: "2", three: "3", four: "4", six: "6",
            five: "5", equal: "=", nine: "9", seven: "7", minus: "-", eight: "8", zero: "0", rightBracket: "]",
            o: "O", u: "U", leftBracket: "[", i: "I", p: "P", returnKey: "↩", l: "L", j: "J", quote: "'",
            k: "K", semicolon: ";", backslash: "\\", comma: ",", slash: "/", n: "N", m: "M", period: ".",
            tab: "Tab", space: "Space", grave: "`", delete: "⌫", escape: "⎋", leftArrow: "←", rightArrow: "→",
            downArrow: "↓", upArrow: "↑", forwardDelete: "⌦", home: "↖", end: "↘", pageUp: "⇞", pageDown: "⇟",
        ]
        for key in functionKeys { map[key.code] = key.name }
        return map
    }()

    public static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
