import AppKit
import ApplicationServices
import Carbon

extension KeyTipController {
    struct ExcelCommand: Identifiable {
        let name: String
        let argumentCount: ClosedRange<Int>
        var parameters = ""
        let summary: String
        var requiresGridFocus = true
        let handler: (KeyTipController, pid_t, [String]) -> Void

        var id: String { name }
        var usage: String { ":" + name + parameters }

        static func shortcut(_ name: String, summary: String, letter: String, flags: CGEventFlags) -> Self {
            Self(name: name, argumentCount: 0...0, summary: summary) { controller, excel, _ in
                guard let key = KeyboardLayout.keyCode(for: letter, flags: flags) else {
                    controller.showCommandError("Tastenkürzel für \(name) im aktuellen Layout nicht gefunden")
                    return
                }
                controller.dismiss()
                SyntheticKeys.post(key, flags: flags, to: excel)
            }
        }

        static func key(_ name: String, summary: String, code: Int, flags: CGEventFlags = []) -> Self {
            Self(name: name, argumentCount: 0...0, summary: summary) { controller, excel, _ in
                controller.dismiss()
                SyntheticKeys.post(CGKeyCode(code), flags: flags, to: excel)
            }
        }
    }

    static let excelCommands: [String: ExcelCommand] = {
        let commands: [ExcelCommand] = [
            .shortcut("undo", summary: "Letzte Excel-Aktion rückgängig machen", letter: "z", flags: .maskCommand),
            .shortcut("redo", summary: "Rückgängig gemachte Excel-Aktion wiederholen", letter: "z", flags: [.maskCommand, .maskShift]),
            .shortcut("copy", summary: "Kopiert eine Celle", letter: "c", flags: [.maskCommand]),
            .shortcut("paste", summary: "Fügt eine Celle ein", letter: "v", flags: [.maskCommand]),
            .key("delete_cell", summary: "Zellinhalte leeren", code: kVK_Delete),
            .key("bold", summary: "Fettschrift umschalten", code: kVK_ANSI_B, flags: .maskCommand),
            .key("italic", summary: "Kursivschrift umschalten", code: kVK_ANSI_I, flags: .maskCommand),
            .init(name: "reset", argumentCount: 0...0, summary: "Zellformatierung entfernen") { controller, excel, _ in
                controller.resetFormats(in: excel)
            },
            .init(name: "fill", argumentCount: 1...1, parameters: " <color>", summary: "Füllfarbe setzen, z. B. #FFCC00 oder none") { controller, excel, arguments in
                controller.fill(arguments[0], in: excel)
            },
            .init(name: "alt", argumentCount: 1...12, parameters: " <tab> [<keys>]", summary: "KeyTip direkt über Bedienungshilfen auslösen", requiresGridFocus: false) { controller, _, arguments in
                controller.runKeyTips(arguments)
            },
            .init(name: "border", argumentCount: 1...4, parameters: " <side> …", summary: "Außenkanten setzen: top, bottom, left, right") { controller, excel, arguments in
                controller.applyBorder(arguments, in: excel)
            },
            .init(name: "cell_step", argumentCount: 2...2, parameters: " <direction> <count>", summary: "Zellen relativ ansteuern (h / j / k / l)") { controller, excel, arguments in
                controller.stepCells(arguments, in: excel)
            },
            .init(name: "cell_row", argumentCount: 1...1, parameters: " <row>", summary: "Zu einer Excel-Zeile springen (gg / G)") { controller, excel, arguments in
                controller.goToRow(arguments[0], in: excel)
            },
            .init(name: "cell_jump", argumentCount: 2...2, parameters: " <direction> <count>", summary: "Zu befüllten Zellen springen (w / b)") { controller, excel, arguments in
                controller.jumpToPopulatedCell(arguments, in: excel)
            },
            .init(name: "underline", argumentCount: 0...0, summary: "Unterstreichung umschalten", requiresGridFocus: false) { controller, excel, _ in
                controller.underline(in: excel)
            },
            .init(name: "select", argumentCount: 1...1, parameters: " <tab>", summary: "Tab im Menüband öffnen", requiresGridFocus: false) { controller, _, arguments in
                controller.selectTab(named: arguments[0])
            },
            .init(name: "help", argumentCount: 1...1, parameters: " excel", summary: "Diese Übersicht anzeigen", requiresGridFocus: false) { controller, excel, arguments in
                controller.showExcelHelp(topic: arguments[0], in: excel)
            },
        ]
        return Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
    }()

    func execute(_ input: String) {
        guard let invocation = ExcelCommandInvocation(input) else {
            showCommandError("Ungültige Excel-Argumente")
            return
        }
        execute(named: invocation.name, arguments: invocation.arguments)
    }

    func execute(named name: String, arguments: [String]) {
        guard let excel = keyTips.process, excel == frontExcel?.processIdentifier else {
            dismiss()
            return
        }
        guard let command = Self.excelCommands[normalize(name)] else {
            showCommandError("Unbekannter Excel-Befehl")
            return
        }
        guard command.argumentCount.contains(arguments.count) else {
            showCommandError("Verwendung: \(command.usage)")
            return
        }
        guard !command.requiresGridFocus || accessibility.isExcelGridFocused(in: excel) else {
            showCommandError("\(command.name) benötigt den Fokus im Zellraster")
            return
        }
        command.handler(self, excel, arguments)
    }

    private func fill(_ color: String, in excel: pid_t) {
        guard let fill = ExcelFill(color: color) else {
            showCommandError("Verwendung: fill <Farbname | #RRGGBB | none>")
            return
        }
        runExcelScript(fill.assignment, in: excel)
    }

    private func applyBorder(_ sides: [String], in excel: pid_t) {
        guard let border = ExcelBorder(sides: sides) else {
            showCommandError("border akzeptiert top, bottom, left und right")
            return
        }
        runExcelScript(border.assignment, in: excel)
    }

    private func stepCells(_ arguments: [String], in excel: pid_t) {
        guard let direction = WorksheetMotion.Direction(rawValue: normalize(arguments[0])),
              let count = Int(arguments[1]), count > 0 else {
            showCommandError("cell_step erwartet left, right, up oder down und eine positive Anzahl")
            return
        }
        let visual = vimMode == .visual
        if count > 64 {
            let motion = WorksheetMotion(target: .step(direction, min(count, WorksheetMotion.maxRow)),
                                         extendsSelection: visual)
            runExcelScript(motion.assignment, in: excel, transientError: true)
            return
        }

        dismiss()
        for _ in 0..<count {
            SyntheticKeys.post(direction.keyCode, flags: visual ? .maskShift : [], to: excel)
        }
    }

    private func goToRow(_ argument: String, in excel: pid_t) {
        guard let row = Int(argument), row >= 0 else {
            showCommandError("cell_row erwartet eine Zeilennummer")
            return
        }
        let target: WorksheetMotion.Target = row == 0 ? .lastUsedRow : .row(min(row, WorksheetMotion.maxRow))
        let motion = WorksheetMotion(target: target, extendsSelection: vimMode == .visual)
        runExcelScript(motion.assignment, in: excel, transientError: true)
    }

    private func jumpToPopulatedCell(_ arguments: [String], in excel: pid_t) {
        guard let direction = PopulatedCellMotion.Direction(rawValue: normalize(arguments[0])),
              let count = Int(arguments[1]), count > 0 else {
            showCommandError("cell_jump erwartet forward oder backward und eine positive Anzahl")
            return
        }
        let motion = PopulatedCellMotion(direction: direction, count: min(count, 16_384), extendsSelection: vimMode == .visual)
        runExcelScript(motion.assignment, in: excel, transientError: true)
    }

    private func runExcelScript(_ assignment: String, in excel: pid_t, transientError: Bool = false) {
        guard let applicationURL = NSRunningApplication(processIdentifier: excel)?.bundleURL else {
            showCommandError("Excel-App konnte nicht gefunden werden")
            return
        }
        if let error = ExcelAppleScript.run(assignment, in: applicationURL) {
            guard keyTips.process == excel, frontExcel?.processIdentifier == excel else { return }
            if transientError {
                dismiss()
                overlay.showTransientMessage(error)
            } else {
                showCommandError(error)
            }
        } else {
            dismiss()
        }
    }

    private func resetFormats(in excel: pid_t) {
        guard accessibility.clearExcelFormats(in: excel) else {
            showCommandError("Excel konnte „Formate löschen“ nicht ausführen")
            return
        }
        dismiss()
    }

    private func underline(in excel: pid_t) {
        let item = currentRibbon().flatMap { ribbon in
            reader.commands(in: ribbon).first { $0.supportsPress && isUnderline($0) }
        }
        dismiss()
        if let item {
            _ = AX.press(item.element)
        } else {
            SyntheticKeys.post(CGKeyCode(kVK_ANSI_U), flags: .maskCommand, to: excel)
        }
    }

    private func selectTab(named title: String) {
        let name = normalize(title)
        let names = WindowsRibbonKeyTips.tab(named: name)?.names ?? [name]
        guard let ribbon = currentRibbon(),
              let tab = reader.tabs(in: ribbon)
                  .first(where: { names.contains(normalize($0.title)) }) else {
            showCommandError("Tab nicht gefunden")
            return
        }
        select(tab)
    }

    private func showExcelHelp(topic: String, in excel: pid_t) {
        guard normalize(topic) == "excel" else {
            showCommandError("Verwendung: help excel")
            return
        }
        dismiss()
        keyTips.process = excel
        keyTips.helpIsOpen = true
        let commands = Self.excelCommands.values.sorted { $0.name < $1.name }
        overlay.showHelp(commands.map { ($0.usage, $0.summary) })
    }

    func showCommandError(_ message: String) {
        overlay.show([], command: message + " · Esc")
        keyTips.commandLine = ""
    }
}
