//
//  RibbonReader.swift
//  Overlay
//
//  Created by Tom Witjes on 18.11.26.
//


import ApplicationServices

final class RibbonReader {

    // MARK: - Public

    func readRibbon(_ ribbon: AXUIElement, includeCommands: Bool = true) -> ExcelRibbon? {
        let children = getChildren(ribbon)
        let tabs = children.compactMap { element -> RibbonTab? in
            let role = getString(element, kAXRoleAttribute)

            guard role == kAXRadioButtonRole || role == "AXTab",
                  let title = getString(element, kAXTitleAttribute)
                    ?? getString(element, kAXDescriptionAttribute)
            else {
                return nil
            }

            return RibbonTab(
                id: title,
                title: title,
                element: element,
                groups: []
            )
        }

        guard includeCommands, let active = tabs.firstIndex(where: { isSelected($0.element) }) else {
            return ExcelRibbon(tabs: tabs)
        }
        var updatedTabs = tabs
        updatedTabs[active].groups = readVisibleGroups(in: children)
        return ExcelRibbon(tabs: updatedTabs)
    }
    
    
    // MARK: - Groups

    
    private func readVisibleGroups(in children: [AXUIElement]) -> [RibbonGroup] {
        guard let scrollArea = children.first(where: {
            getString($0, kAXRoleAttribute) == kAXScrollAreaRole
        }), let viewport = getFrame(scrollArea), !viewport.isEmpty else { return [] }

        return getChildren(scrollArea).enumerated().compactMap { index, group in
            var commands: [RibbonCommand] = []
            collectCommands(from: group, in: viewport, into: &commands)
            guard !commands.isEmpty else { return nil }
            let title = getString(group, kAXTitleAttribute)
                ?? getString(group, kAXDescriptionAttribute)
            return RibbonGroup(
                id: "\(index)-\(title ?? "group")",
                title: title,
                frame: getFrame(group) ?? viewport,
                commands: commands
            )
        }
    }

    // MARK: - Commands

    private func collectCommands(
        from element: AXUIElement,
        in viewport: CGRect,
        into commands: inout [RibbonCommand]
    ) {
        let role = getString(element, kAXRoleAttribute) ?? ""
        var rawActions: CFArray?
        AXUIElementCopyActionNames(element, &rawActions)

        let actions = rawActions as? [String] ?? []

        let title = getString(element, kAXTitleAttribute)
            ?? getString(element, kAXDescriptionAttribute)

        if let title, !actions.isEmpty,
           (getAttribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue != false,
           let frame = getFrame(element),
           viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {

            let identifier = getString(
                element,
                kAXIdentifierAttribute
            )

            commands.append(
                RibbonCommand(
                    id: identifier ?? "\(role)-\(title)",
                    title: title,
                    role: role,
                    identifier: identifier,
                    element: element,
                    frame: frame,
                    actions: actions
                )
            )
        }

        for child in getChildren(element) {
            collectCommands(from: child, in: viewport, into: &commands)
        }
    }


    // MARK: - Helpers

    private func getChildren(
        _ element: AXUIElement
    ) -> [AXUIElement] {

        guard let value = getAttribute(
            element,
            kAXChildrenAttribute as String
        ) else {
            return []
        }

        return value as? [AXUIElement] ?? []
    }

    private func getString(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {

        return getAttribute(element, attribute) as? String
    }

    private func getAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CFTypeRef? {

        var value: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        guard error == .success else {
            return nil
        }

        return value
    }

    func isSelected(_ element: AXUIElement) -> Bool {
        let selected = getAttribute(element, kAXSelectedAttribute) as? NSNumber
        let value = getAttribute(element, kAXValueAttribute) as? NSNumber
        return selected?.boolValue == true || value?.boolValue == true
    }
    
    func getFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = getAttribute(element, kAXPositionAttribute),
              let size = getAttribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              origin.x.isFinite, origin.y.isFinite,
              dimensions.width.isFinite, dimensions.height.isFinite else { return nil }

        return CGRect(origin: origin, size: dimensions)
    }
}
