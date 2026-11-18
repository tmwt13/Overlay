import AppKit
import ApplicationServices
import Carbon
import Combine

final class KeyTipController: ObservableObject {
    @Published private(set) var status = "Bedienungshilfen-Zugriff erforderlich"

    @Published private(set) var vimMode: ExcelVim.Mode = .insert
    @Published var vimEnabled = UserDefaults.standard.object(forKey: "excelVimEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(vimEnabled, forKey: "excelVimEnabled")
            resetVim()
            if vimEnabled {
                startVim()
            } else {
                vim.stop()
                vimState = nil
            }
        }
    }

    @Published private(set) var vimStatus = ""
    private let vim = ExcelVim()
    private var vimProcess: pid_t?
    private var vimState: ExcelVim.Event?
    private var vimCommandVisible = false
    private static let syntheticEventTag: Int64 = 0x584C56494D

    private struct ExcelCommand: Identifiable {
        let name: String
        let argumentCount: ClosedRange<Int>
        var parameters = ""
        let summary: String
        var requiresGridFocus = true
        let handler: (KeyTipController, pid_t, [String]) -> Void

        var id: String { name }
        var usage: String { ":" + name + parameters }

        static func key(_ name: String, summary: String, code: Int, flags: CGEventFlags = []) -> Self {
            Self(name: name, argumentCount: 0...0, summary: summary) { controller, excel, _ in
                controller.dismiss()
                controller.postKey(CGKeyCode(code), flags: flags, to: excel)
            }
        }
    }

    private static let excelCommands: [String: ExcelCommand] = {
        let commands: [ExcelCommand] = [
            .key("delete_cell", summary: "Zellinhalte leeren", code: kVK_Delete),
            .key("bold", summary: "Fettschrift umschalten", code: kVK_ANSI_B, flags: .maskCommand),
            .key("italic", summary: "Kursivschrift umschalten", code: kVK_ANSI_I, flags: .maskCommand),
            .init(name: "reset", argumentCount: 0...0, summary: "Zellformatierung entfernen") { controller, excel, _ in
                controller.resetFormats(in: excel)
            },
            .init(name: "fill", argumentCount: 1...1, parameters: " <color>", summary: "Füllfarbe setzen, z. B. #FFCC00 oder none") { controller, excel, arguments in
                controller.fill(arguments[0], in: excel)
            },
            .init(name: "alt", argumentCount: 1...2, parameters: " <tab> [<key>]", summary: "KeyTip direkt über Bedienungshilfen auslösen", requiresGridFocus: false) { controller, _, arguments in
                controller.runKeyTips(arguments)
            },
            .init(name: "border", argumentCount: 1...4, parameters: " <side> …", summary: "Außenkanten setzen: top, bottom, left, right") { controller, excel, arguments in
                controller.applyBorder(arguments, in: excel)
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

    private enum Target {
        case tab(RibbonTab)
        case command(RibbonCommand)
    }

    private struct Tip {
        let key: String
        let frame: CGRect
        let target: Target
    }

    private struct TabShortcut {
        let key: String
        let names: [String]
    }

    private static let tabShortcuts: [TabShortcut] = [
        .init(key: "h", names: ["home", "start"]),
        .init(key: "n", names: ["insert", "einfügen"]),
        .init(key: "p", names: ["page layout", "layout", "seitenlayout"]),
        .init(key: "m", names: ["formulas", "formeln"]),
        .init(key: "a", names: ["data", "daten"]),
        .init(key: "r", names: ["review", "überprüfen"]),
        .init(key: "w", names: ["view", "ansicht"]),
        .init(key: "l", names: ["developer", "entwicklertools"]),
    ]

    private let accessibility = AccessibilityManager()
    private let reader = RibbonReader()
    private let overlay = KeyTipOverlay()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var optionPressedAt: TimeInterval?
    private var swallowedKeys: Set<Int64> = []
    private var process: pid_t?
    private var tips: [Tip] = []
    private var tabIsOpen = false
    private var helpIsOpen = false
    private var prefix = ""
    private var command: String?
    private var tabLoadID = UUID()
    private var isLoadingTab = false
    private var pendingKeys: [(Int64, String)] = []

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                if app?.processIdentifier != self.vimProcess {
                    self.resetVim()
                }
                if app?.processIdentifier != self.process {
                    self.optionPressedAt = nil
                    self.dismiss()
                }
            }
        }

        vim.onEvent = { [weak self] event in self?.handleVimEvent(event) }
        vim.onExit = { [weak self] in
            self?.resetVim()
            self?.vimState = nil
            self?.vimStatus = "Vim wurde beendet"
        }
        if vimEnabled { startVim() }
        enable(prompt: false)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tap == nil, AXIsProcessTrusted() else { return }
                self.enable(prompt: false)
            }
        }
    }

    func enable(prompt: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let events: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let controller = Unmanaged<KeyTipController>.fromOpaque(context).takeUnretainedValue()
                    return controller.handle(type, event: event) ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = "Kein Tastaturzugriff"
            return
        }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = "Bereit · in Excel kurz ⌥ drücken"
    }

    private var frontExcel: NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.microsoft.Excel" else { return nil }
        return app
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            optionPressedAt = nil
            swallowedKeys.removeAll()
            DispatchQueue.main.async {
                self.resetVim()
                self.dismiss()
            }
        case .flagsChanged:
            let modifiers = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift, .maskSecondaryFn])
            guard key == kVK_Option || key == kVK_RightOption else {
                optionPressedAt = nil
                return false
            }
            if modifiers == .maskAlternate, frontExcel != nil {
                optionPressedAt = ProcessInfo.processInfo.systemUptime
                return false
            }
            let pressedAt = optionPressedAt
            optionPressedAt = nil
            guard modifiers.isEmpty, let pressedAt, let app = frontExcel,
                  ProcessInfo.processInfo.systemUptime - pressedAt < 0.6 else { return false }
            if process != nil {
                process = nil
                DispatchQueue.main.async { self.dismiss() }
            } else {
                process = app.processIdentifier
                DispatchQueue.main.async { self.showTabs() }
            }
        case .keyDown:
            optionPressedAt = nil
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let wasSwallowed = swallowedKeys.contains(key)
            guard !wasSwallowed || isRepeat else { return true }
            guard let excel = frontExcel?.processIdentifier else { return wasSwallowed }

            if !event.flags.intersection([.maskCommand, .maskAlternate]).isEmpty {
                if process != nil { DispatchQueue.main.async { self.dismiss() } }
                return wasSwallowed
            }

            if process == excel {
                if event.flags.contains(.maskControl) {
                    DispatchQueue.main.async { self.dismiss() }
                    return wasSwallowed
                }
                guard !isRepeat else { return wasSwallowed }
                swallowedKeys.insert(key)
                let characters = NSEvent(cgEvent: event)?.characters ?? ""
                DispatchQueue.main.async { self.handleKey(key, characters: characters) }
                return true
            }

            guard vimEnabled else { return wasSwallowed }
            let control = event.flags.contains(.maskControl)
            if vimMode == .insert {
                guard key == kVK_Escape, !isRepeat, !control else { return wasSwallowed }
                let commit = accessibility.commitExcelEdit(in: excel)
                if commit == .useReturn {
                    postKey(CGKeyCode(kVK_Return), flags: [], to: excel)
                }
                if commit == .inactive && !accessibility.isExcelGridFocused(in: excel) {
                    return wasSwallowed
                }
                if !vim.isRunning { startVim() }
                guard vim.isRunning, vimState?.worksheet == true else {
                    if commit != .inactive { swallowedKeys.insert(key) }
                    return commit != .inactive || wasSwallowed
                }
                vimProcess = excel
                vimMode = .normal
                vim.send("\u{1c}\u{0e}")
            } else {
                guard vimProcess == excel, vim.isRunning,
                      accessibility.isExcelGridFocused(in: excel) else {
                    resetVim()
                    return wasSwallowed
                }
                let nativeEvent = NSEvent(cgEvent: event)
                let characters = (control ? nativeEvent?.charactersIgnoringModifiers : nativeEvent?.characters) ?? ""
                guard let input = ExcelVim.terminalKeys(for: key, characters: characters, control: control) else {
                    return wasSwallowed
                }
                vim.send(input)
            }
            swallowedKeys.insert(key)
            return true
        case .keyUp:
            return swallowedKeys.remove(key) != nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            optionPressedAt = nil
            if type != .scrollWheel, vimProcess != nil { resetVim() }
            if process != nil {
                process = nil
                DispatchQueue.main.async { self.dismiss() }
            }
        default:
            break
        }
        return false
    }

    private func currentRibbon() -> AXUIElement? {
        guard let process, process == frontExcel?.processIdentifier else { return nil }
        return accessibility.focusedRibbon(in: process)
    }

    private func showTabs() {
        tabIsOpen = false
        prefix = ""
        tips = tabTips()
        guard !tips.isEmpty else { dismiss(); return }
        render()
    }

    private func tabTips() -> [Tip] {
        guard let ribbon = currentRibbon(),
              let model = reader.readRibbon(ribbon, includeCommands: false) else { return [] }
        var fallback = 0
        return model.tabs.compactMap { tab in
            guard let frame = reader.getFrame(tab.element), !frame.isEmpty else { return nil }
            let key = Self.tabShortcuts.first { $0.names.contains(normalize(tab.title)) }?.key
            fallback += 1
            guard key != nil || fallback < 100 else { return nil }
            return Tip(key: key ?? String(format: "z%02d", fallback), frame: frame, target: .tab(tab))
        }
    }

    private func runKeyTips(_ arguments: [String]) {
        let tabKey = normalize(arguments[0])
        guard let tip = tabTips().first(where: { $0.key == tabKey }),
              case .tab(let tab) = tip.target else {
            showCommandError("Kein Menüband-Tab für KeyTip \(arguments[0])")
            return
        }
        select(tab, commandKey: arguments.dropFirst().first.map(normalize))
    }

    private func select(_ tab: RibbonTab, commandKey: String? = nil) {
        prefix = ""
        tips = []
        overlay.hide()
        let alreadySelected = reader.isSelected(tab.element)
        guard alreadySelected || press(tab.element) else {
            if commandKey != nil {
                showCommandError("Excel konnte den Menüband-Tab nicht öffnen")
            } else {
                showTabs()
            }
            return
        }
        isLoadingTab = true
        tabLoadID = UUID()
        let id = tabLoadID
        DispatchQueue.main.asyncAfter(deadline: .now() + (alreadySelected ? 0 : 0.05)) {
            self.loadCommands(for: tab.title, id: id, retries: 5, commandKey: commandKey)
        }
    }

    private func loadCommands(for title: String, id: UUID, retries: Int, commandKey: String?) {
        guard tabLoadID == id else { return }
        guard let ribbon = currentRibbon() else { dismiss(); return }
        let commands = reader.readRibbon(ribbon)?.tabs
            .first { $0.title == title }?.groups
            .flatMap(\.commands).filter { $0.supportsPress && !$0.frame.isEmpty } ?? []

        if commands.isEmpty, retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.loadCommands(for: title, id: id, retries: retries - 1, commandKey: commandKey)
            }
            return
        }

        isLoadingTab = false
        tabIsOpen = true
        let keys = Array("abcdefghijklmnopqrstuvwxy012456789")
        var index = 0
        var assignedUnderline = false
        tips = commands.compactMap { item in
            if !assignedUnderline, isUnderline(item) {
                assignedUnderline = true
                return Tip(key: "3", frame: item.frame, target: .command(item))
            }
            guard index < keys.count + 99 else { return nil }
            let key = index < keys.count ? String(keys[index]) : String(format: "z%02d", index - keys.count + 1)
            index += 1
            return Tip(key: key, frame: item.frame, target: .command(item))
        }
        let queued = pendingKeys
        pendingKeys.removeAll()
        if let commandKey {
            guard let tip = tips.first(where: { $0.key == commandKey }),
                  case .command(let command) = tip.target else {
                showCommandError("Kein Befehl für KeyTip \(commandKey.uppercased()) in \(title)")
                return
            }
            if press(command.element) {
                dismiss()
            } else {
                showCommandError("Excel konnte „\(command.title)“ nicht ausführen")
            }
            return
        }
        if tips.isEmpty { showTabs() } else { render() }
        for (key, characters) in queued where process != nil {
            handleKey(key, characters: characters)
        }
    }

    private func handleKey(_ key: Int64, characters: String) {
        guard process != nil, process == frontExcel?.processIdentifier else { return }
        if helpIsOpen {
            if key == kVK_Escape { dismiss() }
            return
        }
        if key == kVK_Escape {
            if isLoadingTab {
                tabLoadID = UUID()
                isLoadingTab = false
                pendingKeys.removeAll()
                showTabs()
            } else if tabIsOpen || (command != nil && !tips.isEmpty) {
                command = nil
                showTabs()
            } else {
                dismiss()
            }
            return
        }
        if isLoadingTab {
            if pendingKeys.count < 16 { pendingKeys.append((key, characters)) }
            return
        }
        if var input = command {
            switch key {
            case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter):
                command = nil
                execute(input)
                return
            case Int64(kVK_Delete):
                if !input.isEmpty { input.removeLast() }
            default:
                if !characters.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                   input.count < 100 { input += characters }
            }
            command = input
            render()
            return
        }
        if characters == ":" {
            command = ""
            render()
            return
        }
        let next = prefix + characters.lowercased()
        if !characters.isEmpty, let match = tips.first(where: { $0.key == next }) {
            switch match.target {
            case .tab(let tab): select(tab)
            case .command(let item):
                dismiss()
                _ = press(item.element)
            }
        } else if !characters.isEmpty, tips.contains(where: { $0.key.hasPrefix(next) }) {
            prefix = next
            render()
        } else {
            prefix = ""
            render()
        }
    }

    private func execute(_ input: String) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = input.prefix { !$0.isWhitespace && $0 != "(" }
        var tail = input.dropFirst(name.count)[...]
        // Keep the existing :select("home") spelling alongside :select home.
        if tail.first == "(", tail.last == ")" {
            tail = tail.dropFirst().dropLast()
        }

        let tokens = tail.matches(of: /"([^"]*)"|'([^']*)'|([^\s"']+)/)
        var end = tail.startIndex
        var arguments: [String] = []
        for token in tokens {
            guard tail[end..<token.range.lowerBound].allSatisfy(\.isWhitespace) else {
                showCommandError("Ungültige Excel-Argumente")
                return
            }
            arguments.append(String(token.1 ?? token.2 ?? token.3 ?? ""))
            end = token.range.upperBound
        }
        guard tail[end...].allSatisfy(\.isWhitespace) else {
            showCommandError("Ungültige Excel-Argumente")
            return
        }
        execute(named: String(name), arguments: arguments)
    }

    private func execute(named name: String, arguments: [String]) {
        guard let excel = process, excel == frontExcel?.processIdentifier else {
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

    private func runExcelScript(_ assignment: String, in excel: pid_t) {
        guard let applicationURL = NSRunningApplication(processIdentifier: excel)?.bundleURL else {
            showCommandError("Excel-App konnte nicht gefunden werden")
            return
        }
        if let error = ExcelAppleScript.run(assignment, in: applicationURL) {
            if process == excel, frontExcel?.processIdentifier == excel { showCommandError(error) }
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
        let item = currentRibbon().flatMap { reader.readRibbon($0) }?.tabs
            .flatMap(\.groups).flatMap(\.commands)
            .first { $0.supportsPress && isUnderline($0) }
        dismiss()
        if let item {
            _ = press(item.element)
        } else {
            postKey(CGKeyCode(kVK_ANSI_U), flags: .maskCommand, to: excel)
        }
    }

    private func selectTab(named title: String) {
        let name = normalize(title)
        let names = Self.tabShortcuts.first { $0.names.contains(name) }?.names ?? [name]
        guard let ribbon = currentRibbon(),
              let tab = reader.readRibbon(ribbon, includeCommands: false)?.tabs
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
        process = excel
        helpIsOpen = true
        let commands = Self.excelCommands.values.sorted { $0.name < $1.name }
        overlay.showHelp(commands.map { ($0.usage, $0.summary) })
    }

    private func showCommandError(_ message: String) {
        overlay.show([], command: message + " · Esc")
        command = ""
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags, to process: pid_t) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            event.postToPid(process)
        }
    }

    private func startVim() {
        do {
            try vim.start(commandNames: Self.excelCommands.keys.sorted())
            vimStatus = ""
        } catch {
            vimStatus = "Vim konnte nicht gestartet werden"
        }
    }

    private func handleVimEvent(_ event: ExcelVim.Event) {
        guard let excel = vimProcess, excel == frontExcel?.processIdentifier else {
            if event.mode != nil { vimState = event }
            return
        }

        if event.excelCommand != nil || event.excelAction != nil {
            guard process == nil else { return }
            overlay.hide()
            vimCommandVisible = false
            process = excel
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
        guard event.worksheet == true else { return }
        if vimMode != event.excelMode { vimMode = event.excelMode }

        if process == nil {
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
              process == nil else { return }

        let flags: CGEventFlags = event.excelMode == .visual ? .maskShift : []
        moveCells(row - oldRow, backward: kVK_UpArrow, forward: kVK_DownArrow, flags: flags, to: excel)
        moveCells(column - oldColumn, backward: kVK_LeftArrow, forward: kVK_RightArrow, flags: flags, to: excel)
    }

    private func moveCells(_ distance: Int, backward: Int, forward: Int, flags: CGEventFlags, to excel: pid_t) {
        let key = CGKeyCode(distance < 0 ? backward : forward)
        for _ in 0..<abs(distance) {
            postKey(key, flags: flags, to: excel)
        }
    }

    private func resetVim() {
        if vimProcess != nil { vim.send("\u{1c}\u{0e}") }
        vimProcess = nil
        if vimCommandVisible {
            vimCommandVisible = false
            if process == nil { overlay.hide() }
        }
        if vimMode != .insert { vimMode = .insert }
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isUnderline(_ item: RibbonCommand) -> Bool {
        let title = normalize(item.title)
        return title == "underline" || title == "unterstreichen"
            || title.hasPrefix("underline (") || title.hasPrefix("unterstreichen (")
            || ["underline", "fontunderline"].contains(normalize(item.identifier ?? ""))
    }

    private func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func render() {
        let labels = tips.filter { $0.key.hasPrefix(prefix) }.map {
            KeyTipLabel(text: $0.key, frame: $0.frame)
        }
        overlay.show(labels, command: command.map { ":" + $0 })
    }

    private func dismiss() {
        process = nil
        helpIsOpen = false
        tips = []
        prefix = ""
        command = nil
        tabIsOpen = false
        isLoadingTab = false
        tabLoadID = UUID()
        pendingKeys.removeAll()
        overlay.hide()
    }
}
