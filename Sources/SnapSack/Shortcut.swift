import AppKit
import Carbon.HIToolbox

/// The key combination that takes a screenshot. It's saved in UserDefaults, so it survives restarts.
struct Shortcut: Equatable {
    static let defaultsKey = "screenshotShortcut"
    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), key: "S")

    let keyCode: UInt32
    /// Carbon modifier flags: controlKey, optionKey, shiftKey, cmdKey.
    let modifiers: UInt32
    /// The key as shown to you, e.g. "S" or "Space".
    let key: String

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Built from a key press. Returns nil if it can't be a global shortcut: it needs ⌘, ⌃ or ⌥,
    /// because shift on its own would clash with typing.
    init?(press: KeyPress) {
        let flags = press.modifiers
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        self.keyCode = UInt32(press.keyCode)
        self.modifiers = carbon
        self.key = Shortcut.label(for: press)
    }

    static var current: Shortcut {
        get {
            guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey),
                  let code = stored["keyCode"] as? Int,
                  let modifiers = stored["modifiers"] as? Int,
                  let key = stored["key"] as? String else { return .standard }
            return Shortcut(keyCode: UInt32(code), modifiers: UInt32(modifiers), key: key)
        }
        set {
            UserDefaults.standard.set([
                "keyCode": Int(newValue.keyCode),
                "modifiers": Int(newValue.modifiers),
                "key": newValue.key,
            ], forKey: defaultsKey)
        }
    }

    /// For showing, e.g. "⌃⌥S".
    var display: String { modifierSymbols + key }

    /// The menu item's key equivalent. Empty for keys that a menu can't show, like Space.
    var menuKey: String { key.count == 1 ? key.lowercased() : "" }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    private var modifierSymbols: String {
        // The order macOS itself uses in menus.
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    private static func label(for press: KeyPress) -> String {
        switch Int(press.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        default: return (press.characters ?? "?").uppercased()
        }
    }
}

/// The parts of a key press that matter, copied out of the event so they can be passed between threads.
/// NSEvent itself isn't Sendable.
struct KeyPress: Sendable {
    let keyCode: UInt16
    let flags: UInt
    let characters: String?

    init(_ event: NSEvent) {
        keyCode = event.keyCode
        flags = event.modifierFlags.rawValue
        characters = event.charactersIgnoringModifiers
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: flags).intersection([.command, .control, .option, .shift])
    }
}
