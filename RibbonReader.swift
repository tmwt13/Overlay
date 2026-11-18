//
//  RibbonReader.swift
//  Overlay
//
//  Created by Tom Witjes on 18.11.26.
//


import ApplicationServices

final class RibbonReader {

    // MARK: - Public

    func readRibbon(_ ribbon: AXUIElement) -> ExcelRibbon? {
        let tabs = getChildren(ribbon).compactMap { element -> RibbonTab? in
            let role = getString(element, kAXRoleAttribute)

            guard role == "AXRadioButton",
                  let title = getString(element, kAXTitleAttribute)
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

        let visibleGroups = readVisibleGroups(in: ribbon)

        // Die sichtbaren Gruppen gehören zum aktuell geöffneten Tab.
        let activeTitle = tabs.first(where: {
            isSelected($0.element)
        })?.title

        let updatedTabs = tabs.map { tab in
            RibbonTab(
                id: tab.id,
                title: tab.title,
                element: tab.element,
                groups: tab.title == activeTitle ? visibleGroups : []
            )
        }

        return ExcelRibbon(tabs: updatedTabs)
    }
    
    
    private func inspectAttributes(of element: AXUIElement) {
        var rawNames: CFArray?

        let error = AXUIElementCopyAttributeNames(
            element,
            &rawNames
        )

        guard error == .success,
              let names = rawNames as? [String] else {
            return
        }

        print("    Attributes:")

        for name in names {
            guard let value = getAttribute(element, name) else {
                continue
            }

            print("      \(name): \(value)")
        }
    }

    // MARK: - Groups

    
    private func readVisibleGroups(
        in ribbon: AXUIElement
    ) -> [RibbonGroup] {

        guard let scrollArea = getChildren(ribbon).first(where: {
            getString($0, kAXRoleAttribute) == "AXScrollArea"
        }) else {
            print("Ribbon scroll area not found")
            return []
        }

        let groups = getChildren(scrollArea)
            .filter {
                getString($0, kAXRoleAttribute) == "AXGroup"
            }

        return groups.enumerated().compactMap { index, group in

            inspectAttributes(of: group)

            guard let frame = getFrame(group) else {
                print("Could not get frame for group \(index)")
                return nil
            }

            let title = getString(group, kAXTitleAttribute)
                ?? getString(group, kAXDescriptionAttribute)

            return RibbonGroup(
                id: "\(index)-\(title ?? "group")",
                title: title,
                frame: frame,
                commands: readCommands(in: group)
            )
        }
    }


    // MARK: - Commands

    private func readCommands(
        in group: AXUIElement
    ) -> [RibbonCommand] {

        var commands: [RibbonCommand] = []

        collectCommands(
            from: group,
            into: &commands
        )

        return commands
    }

    
    private func collectCommands(
        from element: AXUIElement,
        into commands: inout [RibbonCommand]
    ) {

        let role = getString(element, kAXRoleAttribute) ?? ""

        var rawActions: CFArray?
        AXUIElementCopyActionNames(element, &rawActions)

        let actions = rawActions as? [String] ?? []

        let title = getString(element, kAXTitleAttribute)
            ?? getString(element, kAXDescriptionAttribute)

        if let title,
           !actions.isEmpty,
           let frame = getFrame(element) {

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
            collectCommands(from: child, into: &commands)
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

    private func isSelected(_ element: AXUIElement) -> Bool {
        guard let value = getAttribute(
            element,
            kAXValueAttribute
        ) else {
            return false
        }

        return (value as? NSNumber)?.boolValue ?? false
    }
    
    private func getFrame(_ element: AXUIElement) -> CGRect? {
        guard let value = getAttribute(
            element,
            kAXFrameAttribute as String
        ),
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var frame = CGRect.zero

        guard AXValueGetValue(
            value as! AXValue,
            .cgRect,
            &frame
        ) else {
            return nil
        }

        return frame
    }
    }
}

