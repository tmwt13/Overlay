import AppKit
import ApplicationServices
import Carbon

extension KeyTipController {
    func currentRibbon() -> AXUIElement? {
        guard let excel = keyTips.process, excel == frontExcel?.processIdentifier else { return nil }
        return accessibility.focusedRibbon(in: excel)
    }

    func showTabs() {
        keyTips.tab = nil
        keyTips.commandPath = ""
        keyTips.menuIsOpen = false
        keyTips.prefix = ""
        keyTips.tips = tabTips()
        guard !keyTips.tips.isEmpty else { dismiss(); return }
        render()
    }

    private func tabTips() -> [RibbonKeyTip] {
        guard let ribbon = currentRibbon() else { return [] }
        var usedKeys: Set<String> = []
        return reader.tabs(in: ribbon).compactMap { tab in
            guard let frame = tab.frame, !frame.isEmpty,
                  let key = WindowsRibbonKeyTips.tab(named: tab.title)?.key,
                  usedKeys.insert(key).inserted else { return nil }
            return RibbonKeyTip(key: key, frame: frame, target: .tab(tab))
        }
    }

    func runKeyTips(_ arguments: [String]) {
        let tabKey = normalize(arguments[0])
        guard let tip = tabTips().first(where: { $0.key == tabKey }),
              case .tab(let tab) = tip.target else {
            showCommandError("Kein Menüband-Tab für KeyTip \(arguments[0])")
            return
        }
        let sequence = arguments.dropFirst().map(normalize).joined()
        select(tab, commandKey: sequence.isEmpty ? nil : sequence)
    }

    func select(_ tab: RibbonTab, commandKey: String? = nil) {
        keyTips.prefix = ""
        keyTips.tips = []
        overlay.hide()
        let alreadySelected = reader.isSelected(tab.element)
        guard alreadySelected || AX.press(tab.element) else {
            if commandKey != nil {
                showCommandError("Excel konnte den Menüband-Tab nicht öffnen")
            } else {
                showTabs()
            }
            return
        }
        keyTips.isLoadingTab = true
        keyTips.tabLoadID = UUID()
        let id = keyTips.tabLoadID
        DispatchQueue.main.async {
            self.loadCommands(for: tab, id: id, attempt: 0, commandKey: commandKey)
        }
    }

    private func loadCommands(for tab: RibbonTab, id: UUID, attempt: Int, commandKey: String?) {
        guard keyTips.tabLoadID == id else { return }
        guard let ribbon = currentRibbon() else { dismiss(); return }
        let commands = reader.commands(in: ribbon, for: tab).filter { !$0.frame.isEmpty }

        if commands.isEmpty, attempt < 6 {
            let delay = min((attempt + 1) * 20, 100)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                self.loadCommands(for: tab, id: id, attempt: attempt + 1, commandKey: commandKey)
            }
            return
        }

        keyTips.isLoadingTab = false
        keyTips.tab = tab
        keyTips.commandPath = WindowsRibbonKeyTips.tab(named: tab.title)?.key ?? ""
        let bindings = WindowsRibbonKeyTips.bindings(for: tab.title)
        keyTips.tips = mappedTips(commands, bindings: bindings)
        if keyTips.tips.isEmpty, commandKey == nil {
            showTabs()
        }
        finishLoading(id: id, requested: commandKey)
    }

    private func finishLoading(id: UUID, requested: String?) {
        let queued = keyTips.pendingKeys
        keyTips.pendingKeys.removeAll()
        if let requested {
            let exact = keyTips.tips.first { $0.key == requested }
            let menu = keyTips.tips.filter { requested.hasPrefix($0.key)
                && !WindowsRibbonKeyTips.submenu(at: keyTips.commandPath + $0.key).isEmpty
            }.max { $0.key.count < $1.key.count }

            guard let tip = exact ?? menu else {
                showCommandError("Kein Befehl für KeyTip \(requested.uppercased())")
                return
            }
            let suffix = String(requested.dropFirst(tip.key.count))
            activate(tip, remaining: suffix.isEmpty ? nil : suffix)
            return
        }

        for (key, characters) in queued where keyTips.process != nil {
            handleKey(key, characters: characters)
        }
        if keyTips.tabLoadID == id, !keyTips.isLoadingTab { render() }
    }

    func handleKey(_ key: Int64, characters: String) {
        guard keyTips.process != nil, keyTips.process == frontExcel?.processIdentifier else { return }
        if keyTips.helpIsOpen {
            if key == kVK_Escape { dismiss() }
            return
        }
        if key == kVK_Escape {
            if keyTips.menuIsOpen, let process = keyTips.process {
                SyntheticKeys.post(CGKeyCode(kVK_Escape), flags: [], to: process)
                let tab = keyTips.tab
                let id = UUID()
                keyTips = KeyTipSession(process: process, tabLoadID: id, isLoadingTab: true)
                overlay.hide()
                DispatchQueue.main.async {
                    guard self.keyTips.tabLoadID == id else { return }
                    if let tab {
                        self.select(tab)
                    } else {
                        self.keyTips.isLoadingTab = false
                        self.showTabs()
                    }
                }
            } else if keyTips.isLoadingTab {
                keyTips.tabLoadID = UUID()
                keyTips.isLoadingTab = false
                keyTips.pendingKeys.removeAll()
                showTabs()
            } else if !keyTips.prefix.isEmpty {
                keyTips.prefix = ""
                render()
            } else if keyTips.tab != nil || (keyTips.commandLine != nil && !keyTips.tips.isEmpty) {
                keyTips.commandLine = nil
                showTabs()
            } else {
                dismiss()
            }
            return
        }
        if keyTips.isLoadingTab {
            if keyTips.pendingKeys.count < 16 { keyTips.pendingKeys.append((key, characters)) }
            return
        }
        if var input = keyTips.commandLine {
            switch key {
            case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter):
                keyTips.commandLine = nil
                execute(input)
                return
            case Int64(kVK_Delete):
                if !input.isEmpty { input.removeLast() }
            default:
                if !characters.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                   input.count < 100 { input += characters }
            }
            keyTips.commandLine = input
            render()
            return
        }
        if characters == ":" {
            keyTips.commandLine = ""
            render()
            return
        }
        let next = keyTips.prefix + characters.lowercased()
        if !characters.isEmpty, let match = keyTips.tips.first(where: { $0.key == next }) {
            activate(match)
        } else if !characters.isEmpty, keyTips.tips.contains(where: { $0.key.hasPrefix(next) }) {
            keyTips.prefix = next
            render()
        } else {
            keyTips.prefix = ""
            render()
        }
    }

    private func mappedTips(_ commands: [RibbonCommand], bindings: [WindowsRibbonKeyTips.Binding]) -> [RibbonKeyTip] {
        var usedElements: [AXUIElement] = []
        return bindings.compactMap { binding in
            guard let command = commands.first(where: { command in
                binding.matches(title: command.title, identifier: command.identifier)
                    && supports(binding.activation, command: command)
                    && !usedElements.contains(where: { CFEqual($0, command.element) })
            }) else { return nil }
            usedElements.append(command.element)
            return RibbonKeyTip(key: binding.key, frame: command.frame,
                                target: .command(command, binding.activation))
        }
    }

    private func supports(_ activation: WindowsRibbonKeyTips.Activation, command: RibbonCommand) -> Bool {
        switch activation {
        case .press:
            command.supportsPress
        case .focus:
            command.role == kAXComboBoxRole || command.role == kAXTextFieldRole || command.supportsPress
        case .menu:
            command.actions.contains(kAXShowMenuAction)
                || (command.supportsPress && [kAXMenuButtonRole, kAXPopUpButtonRole, kAXButtonRole].contains(command.role ?? ""))
        case .splitMenu:
            command.actions.contains(kAXShowMenuAction)
                || (command.supportsPress && command.role == kAXPopUpButtonRole)
        }
    }

    private func activate(_ tip: RibbonKeyTip, remaining: String? = nil) {
        guard case .command(let command, let activation) = tip.target else {
            if case .tab(let tab) = tip.target { select(tab) }
            return
        }
        overlay.hide()

        switch activation {
        case .press:
            if AX.press(command.element) { dismiss(); return }
        case .focus:
            if AX.focus(command.element) || (command.supportsPress && AX.press(command.element)) {
                dismiss()
                return
            }
        case .menu, .splitMenu:
            openMenu(command, at: keyTips.commandPath + tip.key, remaining: remaining)
            return
        }
        showCommandError("Excel konnte „\(command.title)“ nicht ausführen")
    }

    private func openMenu(_ command: RibbonCommand, at path: String, remaining: String?) {
        let action = command.actions.contains(kAXShowMenuAction) ? kAXShowMenuAction : kAXPressAction
        let result = AX.actionResult(action, on: command.element)
        guard result == .success || result == .cannotComplete else {
            showCommandError("Excel konnte „\(command.title)“ nicht öffnen")
            return
        }

        let bindings = WindowsRibbonKeyTips.submenu(at: path)
        guard !bindings.isEmpty else { dismiss(); return }
        keyTips.commandPath = path
        keyTips.menuIsOpen = true
        keyTips.prefix = ""
        keyTips.tips = []
        keyTips.isLoadingTab = true
        keyTips.tabLoadID = UUID()
        let id = keyTips.tabLoadID
        DispatchQueue.main.async {
            self.loadMenu(command, bindings: bindings, id: id, attempt: 0, remaining: remaining)
        }
    }

    private func loadMenu(
        _ command: RibbonCommand, bindings: [WindowsRibbonKeyTips.Binding],
        id: UUID, attempt: Int, remaining: String?
    ) {
        guard keyTips.tabLoadID == id, let process = keyTips.process,
              process == frontExcel?.processIdentifier else { return }
        let commands = reader.menuCommands(for: command.element, in: process)
        keyTips.tips = mappedTips(commands, bindings: bindings)
        if keyTips.tips.isEmpty, attempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds((attempt + 1) * 25)) {
                self.loadMenu(command, bindings: bindings, id: id, attempt: attempt + 1, remaining: remaining)
            }
            return
        }

        keyTips.isLoadingTab = false
        if keyTips.tips.isEmpty, remaining == nil {
            dismiss()
        } else {
            finishLoading(id: id, requested: remaining)
        }
    }

    func isUnderline(_ item: RibbonCommand) -> Bool {
        let title = normalize(item.title)
        return title == "underline" || title == "unterstreichen"
            || title.hasPrefix("underline (") || title.hasPrefix("unterstreichen (")
            || ["underline", "fontunderline"].contains(normalize(item.identifier ?? ""))
    }

    private func render() {
        let labels = keyTips.tips.filter { !$0.frame.isEmpty && $0.key.hasPrefix(keyTips.prefix) }.map {
            KeyTipLabel(text: String($0.key.dropFirst(keyTips.prefix.count)), frame: $0.frame)
        }
        overlay.show(labels, command: keyTips.commandLine.map { ":" + $0 })
    }

    func dismiss() {
        keyTips = KeyTipSession()
        overlay.hide()
    }
}
