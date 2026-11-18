import Carbon
import CoreGraphics

enum KeyboardLayout {
    static func character(for key: CGKeyCode, flags: CGEventFlags) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return character(for: key, flags: flags, source: source)
    }

    static func keyCode(for character: String, flags: CGEventFlags, source: TISInputSource? = nil,
                        matchCase: Bool = false) -> CGKeyCode? {
        guard let source = source ?? TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return (CGKeyCode(0)...CGKeyCode(127)).first { key in
            guard let mapped = self.character(for: key, flags: flags, source: source) else { return false }
            return matchCase ? mapped == character : mapped.lowercased() == character.lowercased()
        }
    }

    private static func character(for key: CGKeyCode, flags: CGEventFlags, source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        let modifiers = (flags.contains(.maskAlternate) ? optionKey : 0)
            | (flags.contains(.maskShift) ? shiftKey : 0)
            | (flags.contains(.maskCommand) ? cmdKey : 0)
        var deadKeyState: UInt32 = 0
        var count = 0
        var result = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), UInt32(modifiers >> 8),
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKeyState, result.count, &count, &result)
        guard status == noErr, count > 0 else { return nil }
        return String(decoding: result.prefix(count), as: UTF16.self)
    }
}
