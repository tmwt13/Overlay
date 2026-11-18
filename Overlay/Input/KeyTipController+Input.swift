import AppKit
import Carbon

extension KeyTipController {
    func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        guard !SyntheticKeys.contains(event) else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            optionPressedAt = nil
            swallowedKeys.removeAll()
            DispatchQueue.main.async {
                self.resetVim()
                self.dismiss()
            }
        case .flagsChanged:
            handleOption(key: key, flags: event.flags)
        case .keyDown:
            optionPressedAt = nil
            return handleKeyDown(key, event: event)
        case .keyUp:
            return swallowedKeys.remove(key) != nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            optionPressedAt = nil
            if type == .leftMouseDown, event.getIntegerValueField(.mouseEventClickState) > 1,
               vimProcess != nil { resetVim() }
            if keyTips.process != nil {
                keyTips.process = nil
                DispatchQueue.main.async { self.dismiss() }
            }
        default:
            break
        }
        return false
    }

    private func handleOption(key: Int64, flags: CGEventFlags) {
        let modifiers = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift, .maskSecondaryFn])
        guard key == kVK_Option || key == kVK_RightOption else {
            optionPressedAt = nil
            return
        }
        if modifiers == .maskAlternate, frontExcel != nil {
            optionPressedAt = ProcessInfo.processInfo.systemUptime
            return
        }

        let pressedAt = optionPressedAt
        optionPressedAt = nil
        guard modifiers.isEmpty, let pressedAt, let app = frontExcel,
              ProcessInfo.processInfo.systemUptime - pressedAt < 0.6 else { return }

        if keyTips.process != nil {
            keyTips.process = nil
            DispatchQueue.main.async { self.dismiss() }
        } else {
            keyTips.process = app.processIdentifier
            DispatchQueue.main.async { self.showTabs() }
        }
    }

    private func handleKeyDown(_ key: Int64, event: CGEvent) -> Bool {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let wasSwallowed = swallowedKeys.contains(key)
        guard !wasSwallowed || isRepeat else { return true }
        guard let excel = frontExcel?.processIdentifier else { return wasSwallowed }

        if vimEnabled, keyTips.process == nil, vimMode == .insert, vimCommitID == nil,
           key != kVK_Escape, event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            recordExcelInsertKey(key, event: event, in: excel)
        }

        let isVimAtSign = event.flags.contains(.maskAlternate) && !event.flags.contains(.maskControl)
            && vimEnabled && vimMode != .insert
            && keyTips.process == nil && VimTerminalKeys.isAtSign(event)
        if event.flags.contains(.maskCommand) || (event.flags.contains(.maskAlternate) && !isVimAtSign) {
            if keyTips.process != nil { DispatchQueue.main.async { self.dismiss() } }
            return wasSwallowed
        }

        if keyTips.process == excel {
            if event.flags.contains(.maskControl) {
                DispatchQueue.main.async { self.dismiss() }
                return wasSwallowed
            }
            guard !isRepeat else { return wasSwallowed }

            let characters = NSEvent(cgEvent: event)?.characters ?? ""
            DispatchQueue.main.async { self.handleKey(key, characters: characters) }
        } else {
            guard vimEnabled, handleVimKey(key, event: event, isRepeat: isRepeat, atSign: isVimAtSign, in: excel) else {
                return wasSwallowed
            }
        }

        swallowedKeys.insert(key)
        return true
    }
}
