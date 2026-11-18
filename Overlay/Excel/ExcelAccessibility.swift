import ApplicationServices

struct ExcelAccessibility {
    enum EditCommit {
        case inactive
        case committed
        case useReturn
    }

    func commitExcelEdit(in process: pid_t) -> EditCommit {
        let app = AX.application(process, timeout: 0.05)
        guard let window = AX.element(kAXFocusedWindowAttribute, of: app),
              let accept = AX.children(of: window).first(where: {
                  AX.string(kAXIdentifierAttribute, of: $0) == "EnterButton"
              }) else { return .inactive }

        if AX.boolean(kAXEnabledAttribute, of: accept) == true {
            return AX.press(accept) ? .committed : .useReturn
        }
        if let focused = AX.element(kAXFocusedUIElementAttribute, of: app),
           AX.string(kAXIdentifierAttribute, of: focused) == "XLFormulaEditor" {
            return .useReturn
        }
        return .inactive
    }

    func isExcelGridFocused(in process: pid_t) -> Bool {
        gridFocus(in: process) == true
    }

    func gridFocus(in process: pid_t) -> Bool? {
        let app = AX.application(process, timeout: 0.05)
        guard let focused = AX.element(kAXFocusedUIElementAttribute, of: app),
              let role = AX.role(of: focused) else { return nil }
        return role == kAXLayoutAreaRole
    }

    func focusedWindowFrame(in process: pid_t) -> CGRect? {
        let app = AX.application(process, timeout: 0.05)
        guard let window = AX.element(kAXFocusedWindowAttribute, of: app) else { return nil }
        let attributes = AX.attributes([kAXPositionAttribute, kAXSizeAttribute, kAXSubroleAttribute], of: window)
        let subrole = attributes[kAXSubroleAttribute] as? String
        guard subrole != kAXDialogSubrole, subrole != kAXSystemDialogSubrole else { return nil }
        return AX.frame(in: attributes)
    }

    func focusedRibbon(in process: pid_t) -> AXUIElement? {
        let app = AX.application(process, timeout: 0.2)
        guard let window = AX.element(kAXFocusedWindowAttribute, of: app) else { return nil }
        return AX.children(of: window).first { AX.role(of: $0) == kAXTabGroupRole }
    }

    func clearExcelFormats(in process: pid_t) -> Bool {
        let app = AX.application(process, timeout: 0.2)
        guard let menuBar = AX.element(kAXMenuBarAttribute, of: app),
              let edit = AX.children(of: menuBar).first(where: {
                  AX.string(kAXIdentifierAttribute, of: $0) == "EditMenu_MenuItem"
                    || hasMenuTitle($0, names: ["Edit", "Bearbeiten"])
              }),
              let clear = menuItem(in: edit, named: ["Clear", "Löschen", "Inhalte löschen"]),
              let formats = menuItem(in: clear, named: ["Formats", "Clear Formats", "Formate", "Formate löschen"]),
              AX.boolean(kAXEnabledAttribute, of: formats) == true else { return false }
        return AX.press(formats)
    }

    private func menuItem(in parent: AXUIElement, named names: [String]) -> AXUIElement? {
        // macOS represents submenu entries as children of an AXMenu wrapper.
        for child in AX.children(of: parent) {
            switch AX.role(of: child) {
            case kAXMenuItemRole where hasMenuTitle(child, names: names):
                return child
            case kAXMenuRole:
                if let item = menuItem(in: child, named: names) { return item }
            default:
                break
            }
        }
        return nil
    }

    private func hasMenuTitle(_ element: AXUIElement, names: [String]) -> Bool {
        guard let title = AX.string(kAXTitleAttribute, of: element) else { return false }
        return names.contains { title.caseInsensitiveCompare($0) == .orderedSame }
    }
}
