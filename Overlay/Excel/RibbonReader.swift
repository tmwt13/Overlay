import ApplicationServices

struct RibbonReader {
    private static let tabAttributes = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        kAXPositionAttribute, kAXSizeAttribute
    ]
    private static let selectionAttributes = [kAXSelectedAttribute, kAXValueAttribute]
    private static let commandAttributes = [
        kAXChildrenAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXIdentifierAttribute, kAXRoleAttribute
    ]

    func tabs(in ribbon: AXUIElement) -> [RibbonTab] {
        AX.children(of: ribbon).compactMap { element in
            let attributes = AX.attributes(Self.tabAttributes, of: element)
            guard isTab(attributes[kAXRoleAttribute] as? String),
                  let title = title(in: attributes) else { return nil }
            return RibbonTab(title: title, element: element, frame: AX.frame(in: attributes))
        }
    }

    func commands(in ribbon: AXUIElement, for tab: RibbonTab? = nil) -> [RibbonCommand] {
        let selected = tab.flatMap { selection(of: $0.element) }
        if selected == false { return [] }

        let children = AX.children(of: ribbon)
        if selected == nil {
            guard children.contains(where: { element in
                guard isTab(AX.role(of: element)), isSelected(element) else { return false }
                guard let tab else { return true }
                return AX.string(kAXTitleAttribute, of: element) == tab.title
                    || AX.string(kAXDescriptionAttribute, of: element) == tab.title
            }) else { return [] }
        }
        guard let scrollArea = children.first(where: { AX.role(of: $0) == kAXScrollAreaRole }) else {
            return []
        }

        let attributes = AX.attributes(
            [kAXChildrenAttribute, kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute],
            of: scrollArea
        )
        guard let viewport = AX.frame(in: attributes), !viewport.isEmpty else { return [] }

        // Excel can report the new selected tab while the previous tab's controls are still visible.
        let suffix = " Tab Commands"
        if let tab, let title = attributes[kAXTitleAttribute] as? String, title.hasSuffix(suffix) {
            let displayedTab = String(title.dropLast(suffix.count))
            if displayedTab.caseInsensitiveCompare(tab.title) != .orderedSame,
               children.contains(where: { element in
                   isTab(AX.role(of: element)) && AX.string(kAXTitleAttribute, of: element) == displayedTab
               }) {
                return []
            }
        }

        var commands: [RibbonCommand] = []
        for child in attributes[kAXChildrenAttribute] as? [AXUIElement] ?? [] {
            collectCommands(from: child, in: viewport, into: &commands)
        }
        return commands
    }

    func isSelected(_ element: AXUIElement) -> Bool {
        selection(of: element) == true
    }

    private func selection(of element: AXUIElement) -> Bool? {
        let attributes = AX.attributes(Self.selectionAttributes, of: element)
        let selected = (attributes[kAXSelectedAttribute] as? NSNumber)?.boolValue
        let value = (attributes[kAXValueAttribute] as? NSNumber)?.boolValue
        if selected == true || value == true { return true }
        return selected ?? value
    }

    private func isTab(_ role: String?) -> Bool {
        role == kAXRadioButtonRole || role == "AXTab"
    }

    private func title(in attributes: [String: CFTypeRef]) -> String? {
        attributes[kAXTitleAttribute] as? String ?? attributes[kAXDescriptionAttribute] as? String
    }

    private func collectCommands(
        from element: AXUIElement,
        in viewport: CGRect,
        into commands: inout [RibbonCommand]
    ) {
        let attributes = AX.attributes(Self.commandAttributes, of: element)
        if let title = title(in: attributes),
           (attributes[kAXEnabledAttribute] as? NSNumber)?.boolValue != false,
           let frame = AX.frame(in: attributes),
           viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {
            let role = attributes[kAXRoleAttribute] as? String
            let actions = AX.actions(of: element)
            if actions.contains(kAXPressAction) || actions.contains(kAXShowMenuAction)
                || role == kAXComboBoxRole || role == kAXTextFieldRole {
                commands.append(RibbonCommand(title: title,
                                              identifier: attributes[kAXIdentifierAttribute] as? String,
                                              role: role, actions: actions, element: element, frame: frame))
            }
        }
        for child in attributes[kAXChildrenAttribute] as? [AXUIElement] ?? [] {
            collectCommands(from: child, in: viewport, into: &commands)
        }
    }
}
