import AppKit
import Carbon

enum VimTerminalKeys {
    // Vim recognizes Ctrl-\ Ctrl-N as a transition to Normal mode.
    static let normalMode = "\u{1c}\u{0e}"

    static func mirroredInsert(_ keys: String) -> String {
        "\u{1b}[97~" + keys + "\u{1b}[98~"
    }

    static func isAtSign(_ event: CGEvent) -> Bool {
        if NSEvent(cgEvent: event)?.characters == "@" { return true }
        let key = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        return KeyboardLayout.character(for: key, flags: event.flags) == "@"
    }

    static func encode(_ key: Int64, characters: String, control: Bool) -> String? {
        let special: String?
        switch key {
        case Int64(kVK_Escape): special = "\u{1b}"
        case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter): special = "\r"
        case Int64(kVK_Delete): special = "\u{7f}"
        case Int64(kVK_ForwardDelete): special = "\u{1b}[3~"
        case Int64(kVK_Tab): special = "\t"
        case Int64(kVK_LeftArrow): special = "\u{1b}OD"
        case Int64(kVK_RightArrow): special = "\u{1b}OC"
        case Int64(kVK_UpArrow): special = "\u{1b}OA"
        case Int64(kVK_DownArrow): special = "\u{1b}OB"
        default: special = nil
        }
        if let special { return special }
        if control, let scalar = characters.lowercased().unicodeScalars.first,
           (97...122).contains(scalar.value), let character = UnicodeScalar(scalar.value - 96) {
            return String(character)
        }
        guard !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ $0.value < 0xf700 || $0.value > 0xf8ff }) else { return nil }
        return characters
    }
}
