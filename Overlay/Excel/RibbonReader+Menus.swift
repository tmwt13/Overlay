import ApplicationServices

extension RibbonReader {
    func menuCommands(for origin: AXUIElement, in process: pid_t) -> [RibbonCommand] {
        let app = AX.application(process, timeout: 0.06)
        var candidates = AX.children(of: origin).filter(isMenuElement)
        var focused = AX.element(kAXFocusedUIElementAttribute, of: app)
        for _ in 0..<4 {
            guard let element = focused else { break }
            if isMenuContainer(element) {
                candidates.append(element)
                break
            }
            if AX.role(of: element) == kAXWindowRole { break }
            focused = AX.element(kAXParentAttribute, of: element)
        }
        if let window = AX.element(kAXFocusedWindowAttribute, of: app) {
            candidates.append(contentsOf: AX.children(of: window).filter(isMenuContainer))
        }

        var commands: [RibbonCommand] = []
        for element in candidates {
            collectMenuCommands(from: element, into: &commands)
        }
        return commands
    }

    private func isMenuContainer(_ element: AXUIElement) -> Bool {
        let role = AX.role(of: element)
        return role == kAXMenuRole || role == "AXPopover"
    }

    private func isMenuElement(_ element: AXUIElement) -> Bool {
        isMenuContainer(element) || AX.role(of: element) == kAXMenuItemRole
    }

    private func collectMenuCommands(from element: AXUIElement, into commands: inout [RibbonCommand]) {
        let attributes = AX.attributes([
            kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXChildrenAttribute
        ], of: element)
        let role = attributes[kAXRoleAttribute] as? String
        if role == kAXMenuItemRole || role == kAXButtonRole,
           (attributes[kAXEnabledAttribute] as? NSNumber)?.boolValue != false,
           let title = attributes[kAXTitleAttribute] as? String ?? attributes[kAXDescriptionAttribute] as? String,
           !commands.contains(where: { CFEqual($0.element, element) }) {
            let actions = AX.actions(of: element)
            if actions.contains(kAXPressAction) {
                commands.append(RibbonCommand(title: title, identifier: attributes[kAXIdentifierAttribute] as? String,
                                              role: role, actions: actions, element: element,
                                              frame: AX.frame(in: attributes) ?? .zero))
            }
            // Descend into a submenu only after that submenu is opened.
            return
        }
        for child in attributes[kAXChildrenAttribute] as? [AXUIElement] ?? [] {
            collectMenuCommands(from: child, into: &commands)
        }
    }
}
