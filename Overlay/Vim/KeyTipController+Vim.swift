import AppKit
import ApplicationServices
import Carbon

extension KeyTipController {
    func handleVimKey(_ key: Int64, event: CGEvent, isRepeat: Bool, atSign: Bool, in excel: pid_t) -> Bool {
        let control = event.flags.contains(.maskControl)
        if vimMode == .insert, vimCommitID == nil {
            guard key == kVK_Escape, !isRepeat, !control else { return false }
            return leaveExcelInsertMode(in: excel)
        }

        guard vimProcess == excel, vim.isRunning else {
            resetVim()
            return false
        }

        // A transient AX timeout must not put a Normal-mode keystroke into a cell.
        if vimCommitID == nil {
            guard let gridFocused = accessibility.gridFocus(in: excel) else { return true }
            guard gridFocused else {
                resetVim()
                return false
            }
        }

        let nativeEvent = NSEvent(cgEvent: event)
        let characters = atSign ? "@" : (control ? nativeEvent?.charactersIgnoringModifiers : nativeEvent?.characters) ?? ""
        guard let input = VimTerminalKeys.encode(key, characters: characters, control: control) else {
            return false
        }
        vim.send(input)
        return true
    }

    func recordExcelInsertKey(_ key: Int64, event: CGEvent, in excel: pid_t) {
        guard vimProcess == excel, vimState?.recordingRegister != nil,
              let native = NSEvent(cgEvent: event) else { return }

        let input: String
        switch key {
        case Int64(kVK_Tab):
            input = event.flags.contains(.maskShift) ? "\u{1b}[Z" : "\t"
        case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter):
            guard !event.flags.contains(.maskAlternate) else { return }
            input = "\r"
        case Int64(kVK_Delete):
            input = "\u{7f}"
        default:
            guard let text = native.characters, !text.isEmpty,
                  text.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0) && !(0xf700...0xf8ff).contains($0.value)
                  }) else { return }
            input = text
        }
        vim.send(VimTerminalKeys.mirroredInsert(input))
    }

    private func leaveExcelInsertMode(in excel: pid_t) -> Bool {
        let commit = accessibility.commitExcelEdit(in: excel)
        if commit == .useReturn {
            SyntheticKeys.post(CGKeyCode(kVK_Return), flags: [], to: excel)
        }
        if commit == .inactive && !accessibility.isExcelGridFocused(in: excel) {
            return false
        }

        if !vim.isRunning { startVim() }
        guard vim.isRunning, vimState?.worksheet == true else { return commit != .inactive }

        vimProcess = excel
        vimInsertNeedsCommit = false
        vimMode = .normal
        let wasRecordingInsert = vimState?.excelMode == .insert && vimState?.recordingRegister != nil
        vim.send(wasRecordingInsert ? "\u{1b}" : VimTerminalKeys.normalMode)
        return true
    }

    func startVim() {
        do {
            let directory = URL.applicationSupportDirectory.appendingPathComponent("Excel KeyTips", isDirectory: true)
            try vim.start(commandNames: Self.excelCommands.keys.sorted(),
                          registerFile: directory.appendingPathComponent("registers.viminfo"))
            vimStatus = ""
        } catch {
            vimStatus = "Vim konnte nicht gestartet werden"
        }
    }

    func handleVimEvent(_ event: ExcelVim.Event) {
        guard let excel = vimProcess, excel == frontExcel?.processIdentifier else {
            if event.mode != nil { vimState = event }
            return
        }

        if vimCommitID != nil {
            deferredVimEvents.append(event)
            return
        }
        if let replay = event.insertInput {
            applyVimInsert(replay, text: event.insertText, in: excel)
            return
        }

        if event.excelCommand != nil || event.excelAction != nil {
            guard keyTips.process == nil else { return }
            overlay.hide()
            vimCommandVisible = false
            keyTips.process = excel
            if let input = event.excelCommand {
                execute(input)
            } else if let name = event.excelAction, let arguments = event.arguments {
                execute(named: name, arguments: arguments)
            } else {
                showCommandError("Unbekannter Excel-Befehl oder ungültige Argumente")
            }
            return
        }

        let previous = vimState
        vimState = event
        if previous?.recordingRegister != event.recordingRegister {
            requestModeIndicatorUpdate()
        }
        guard event.worksheet == true else { return }
        if vimMode != event.excelMode { vimMode = event.excelMode }

        if keyTips.process == nil {
            if let input = event.command {
                overlay.show([], command: ":" + input)
                vimCommandVisible = true
            } else if vimCommandVisible {
                overlay.hide()
                vimCommandVisible = false
            }
        }

        guard previous?.worksheet == true,
              event.excelMode != .insert, previous?.excelMode != .insert,
              event.command == nil, previous?.command == nil,
              event.mode?.first != "c", previous?.mode?.first != "c",
              let row = event.row, let column = event.column,
              let oldRow = previous?.row, let oldColumn = previous?.column,
              keyTips.process == nil else { return }

        let flags: CGEventFlags = event.excelMode == .visual ? .maskShift : []
        moveCells(row - oldRow, backward: kVK_UpArrow, forward: kVK_DownArrow, flags: flags, to: excel)
        moveCells(column - oldColumn, backward: kVK_LeftArrow, forward: kVK_RightArrow, flags: flags, to: excel)
    }

    private func applyVimInsert(_ input: ExcelVim.InsertInput, text: String?, in excel: pid_t) {
        switch input {
        case .text:
            if let text, !text.isEmpty {
                vimInsertNeedsCommit = true
                SyntheticKeys.type(text, to: excel)
            }
        case .tab, .backTab:
            vimInsertNeedsCommit = false
            let flags: CGEventFlags = input == .backTab ? .maskShift : []
            SyntheticKeys.post(CGKeyCode(kVK_Tab), flags: flags, to: excel)
        case .backspace:
            vimInsertNeedsCommit = true
            SyntheticKeys.post(CGKeyCode(kVK_Delete), flags: [], to: excel)
        case .submit:
            vimInsertNeedsCommit = false
            SyntheticKeys.post(CGKeyCode(kVK_Return), flags: [], to: excel)
        case .commit:
            guard vimInsertNeedsCommit else { return }
            vimInsertNeedsCommit = false
            let id = UUID()
            vimCommitID = id
            scheduleVimCommit(id, in: excel, retries: 3)
        }
    }

    private func scheduleVimCommit(_ id: UUID, in excel: pid_t, retries: Int) {
        // Excel processes synthetic typing asynchronously. Wait for its editor before committing.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(35)) { [weak self] in
            guard let self, self.vimCommitID == id else { return }
            guard self.vimProcess == excel, self.frontExcel?.processIdentifier == excel else {
                self.resetVim()
                return
            }
            switch self.accessibility.commitExcelEdit(in: excel) {
            case .inactive where retries > 0:
                self.scheduleVimCommit(id, in: excel, retries: retries - 1)
                return
            case .useReturn:
                SyntheticKeys.post(CGKeyCode(kVK_Return), flags: [], to: excel)
            case .inactive, .committed:
                break
            }

            self.vimCommitID = nil
            let queued = self.deferredVimEvents
            self.deferredVimEvents.removeAll()
            for event in queued { self.handleVimEvent(event) }
        }
    }

    private func moveCells(_ distance: Int, backward: Int, forward: Int, flags: CGEventFlags, to excel: pid_t) {
        let key = CGKeyCode(distance < 0 ? backward : forward)
        for _ in 0..<abs(distance) {
            SyntheticKeys.post(key, flags: flags, to: excel)
        }
    }

    func resetVim() {
        vimInsertNeedsCommit = false
        vimCommitID = nil
        deferredVimEvents.removeAll()
        if vimProcess != nil { vim.send(VimTerminalKeys.normalMode) }
        vimProcess = nil
        if vimCommandVisible {
            vimCommandVisible = false
            if keyTips.process == nil { overlay.hide() }
        }
        if vimMode != .insert { vimMode = .insert }
    }
}
