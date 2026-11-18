import CoreGraphics
import Darwin

enum SyntheticKeys {
    private static let eventTag: Int64 = 0x584C56494D

    static func contains(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == eventTag
    }

    static func type(_ text: String, to recipient: pid_t) {
        let units = Array(text.utf16)
        // Excel can consult the hardware key as well as the Unicode payload.
        let plain = KeyboardLayout.keyCode(for: text, flags: [], matchCase: true)
        let shifted = plain == nil ? KeyboardLayout.keyCode(for: text, flags: .maskShift, matchCase: true) : nil
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: plain ?? shifted ?? 0, keyDown: isDown) else { continue }
            event.flags = shifted == nil ? [] : .maskShift
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.postToPid(recipient)
        }
    }

    static func post(_ key: CGKeyCode, flags: CGEventFlags, to recipient: pid_t) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.postToPid(recipient)
        }
    }
}
