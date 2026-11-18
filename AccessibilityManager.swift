//
//  AccessibilityManager.swift
//  MyApp
//
//  Created by Tom Witjes on 18.11.26.
//


import ApplicationServices
import AppKit

final class AccessibilityManager {

    func inspectExcel() {
        // Check Accessibility permission
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            print("Accessibility permission required.")
            return
        }
        
        // Find Excel process
        guard let excel = NSRunningApplication
            .runningApplications(
                withBundleIdentifier: "com.microsoft.Excel"
            )
            .first else {
            print("Excel is not running.")
            return
        }

        let app = AXUIElementCreateApplication(excel.processIdentifier)

        AXUIElementSetMessagingTimeout(app, 5.0)

        print("Inspecting Microsoft Excel")
        print("==========================")

        //inspectWindows(of: app)
        
        print("1. Starting Excel inspection")

        guard let windowValue = getAttribute(
            app,
            kAXFocusedWindowAttribute as String
        ) else {
            print("ERROR: No focused window")
            return
        }

        print("2. Focused window found")

        let window = windowValue as! AXUIElement

        print("3. Window children:")
        for child in getChildren(window) {
            let role = getAttribute(child, kAXRoleAttribute as String) as? String ?? "?"
            let title = getAttribute(child, kAXTitleAttribute as String) as? String ?? "?"
            let identifier = getAttribute(child, kAXIdentifierAttribute as String) as? String ?? "?"

            print("Role: \(role), Title: \(title), Identifier: \(identifier)")
        }

        print("4. Searching for ribbon")

        if let ribbon = findRibbon(in: window) {
            print("5. Ribbon found!")

            inspectRibbon(ribbon)
            selectRibbonTab(ribbon, title: "Home")
            inspectRibbonCommands(ribbon)
            
            inspectAllRibbonTabs(ribbon)
        } else {
            print("ERROR: Ribbon not found")
        }
    }

    private func inspect(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) {
        guard depth <= maxDepth else { return }

        let indent = String(repeating: "  ", count: depth)

        let role = attribute(element, kAXRoleAttribute)
        let title = attribute(element, kAXTitleAttribute)
        let description = attribute(element, kAXDescriptionAttribute)
        let identifier = attribute(element, kAXIdentifierAttribute)

        print("\(indent)\(role ?? "?") | \(title ?? "") | \(description ?? "") | \(identifier ?? "")")

        var children: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        )

        guard error == .success,
              let children = children as? [AXUIElement] else {
            return
        }

        for child in children {
            inspect(
                element: child,
                depth: depth + 1,
                maxDepth: maxDepth
            )
        }
    }

    private func attribute(
        _ element: AXUIElement,
        _ name: String
    ) -> String? {
        var value: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        )

        guard error == .success, let value else {
            return nil
        }

        return String(describing: value)
    }
    
    
   
    private func inspectWindows(of app: AXUIElement) {
        let attributes: [String] = [
            kAXWindowsAttribute as String,
            kAXFocusedWindowAttribute as String,
            kAXMainWindowAttribute as String
        ]

        for name in attributes {
            print("\nATTRIBUTE: \(name)")
            print("========================")

            var value: CFTypeRef?

            let error = AXUIElementCopyAttributeValue(
                app,
                name as CFString,
                &value
            )

            print("Error: \(error.rawValue)")
            print("Value: \(String(describing: value))")

            guard error == .success, let value else {
                continue
            }

            if let windows = value as? [AXUIElement] {
                print("Number of windows: \(windows.count)")

                for (index, window) in windows.enumerated() {
                    print("\nWindow \(index):")
                    inspect(element: window, depth: 0, maxDepth: 15)
                }
            } else if CFGetTypeID(value) == AXUIElementGetTypeID() {
                print("Single AXUIElement:")
                inspect(element: value as! AXUIElement, depth: 0, maxDepth: 15)
            }
        }
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

    private func getChildren(
        _ element: AXUIElement
    ) -> [AXUIElement] {
        return getAttribute(element, kAXChildrenAttribute as String)
            as? [AXUIElement] ?? []
    }
    
    enum EditCommit {
        case inactive
        case committed
        case useReturn
    }

    func commitExcelEdit(in process: pid_t) -> EditCommit {
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let value = getAttribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return .inactive }
        let window = value as! AXUIElement
        guard let accept = getChildren(window).first(where: {
            getAttribute($0, kAXIdentifierAttribute) as? String == "EnterButton"
        }) else { return .inactive }
        guard (getAttribute(accept, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else {
            if let focused = getAttribute(app, kAXFocusedUIElementAttribute),
               CFGetTypeID(focused) == AXUIElementGetTypeID(),
               getAttribute(focused as! AXUIElement, kAXIdentifierAttribute) as? String == "XLFormulaEditor" {
                return .useReturn
            }
            return .inactive
        }
        return AXUIElementPerformAction(accept, kAXPressAction as CFString) == .success
            ? .committed : .useReturn
    }

    func isExcelGridFocused(in process: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let focused = getAttribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        return getAttribute(element, kAXRoleAttribute) as? String == kAXLayoutAreaRole
    }

    func clearExcelFormats(in process: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let value = getAttribute(app, kAXMenuBarAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }

        let menuBar = value as! AXUIElement
        guard let edit = getChildren(menuBar).first(where: {
            getAttribute($0, kAXIdentifierAttribute) as? String == "EditMenu_MenuItem"
                || hasMenuTitle($0, names: ["Edit", "Bearbeiten"])
        }), let clear = menuItem(in: edit, named: ["Clear", "Löschen", "Inhalte löschen"]),
        let formats = menuItem(in: clear, named: ["Formats", "Clear Formats", "Formate", "Formate löschen"]),
        (getAttribute(formats, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { return false }

        return AXUIElementPerformAction(formats, kAXPressAction as CFString) == .success
    }

    private func menuItem(in parent: AXUIElement, named names: [String]) -> AXUIElement? {
        // macOS represents submenu entries as children of an AXMenu wrapper.
        for child in getChildren(parent) {
            switch getAttribute(child, kAXRoleAttribute) as? String {
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
        guard let title = getAttribute(element, kAXTitleAttribute) as? String else { return false }
        return names.contains { title.caseInsensitiveCompare($0) == .orderedSame }
    }

    func focusedRibbon(in process: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let value = getAttribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return findRibbon(in: value as! AXUIElement)
    }

    private func findRibbon(in window: AXUIElement) -> AXUIElement? {
        for child in getChildren(window) {
            let role = getAttribute(
                child,
                kAXRoleAttribute as String
            ) as? String

            if role == "AXTabGroup" {
                print("Ribbon found!")
                return child
            }
        }

        print("Ribbon not found")
        return nil
    }
    
    
    private func inspectRibbon(_ ribbonElement: AXUIElement) {
        print("\nRIBBON TABS")
        print("===========")

        let children = getChildren(ribbonElement)

        for child in children {
            guard getAttribute(
                child,
                kAXRoleAttribute as String
            ) as? String == "AXRadioButton" else {
                continue
            }

            let title = getAttribute(
                child,
                kAXTitleAttribute as String
            ) as? String ?? "Unknown"

            print("Tab: \(title)")
        }

        // Read complete Ribbon model
        let reader = RibbonReader()

        guard let ribbonModel = reader.readRibbon(ribbonElement) else {
            return
        }

        printRibbonModel(ribbonModel)
    }

    
    private func printRibbonModel(_ ribbon: ExcelRibbon) {
        print("\nRIBBON MODEL")
        print("============")

        for tab in ribbon.tabs {
            print("\nTAB: \(tab.title)")

            for group in tab.groups {
                print("  GROUP: \(group.title ?? "Unknown")")
                print("    FRAME: \(group.frame)")

                for command in group.commands {
                    print("    COMMAND: \(command.title)")
                    print("      FRAME: \(command.frame)")
                    print("      ACTIONS: \(command.actions)")
                }
            }
        }
    }

    private func selectRibbonTab(
        _ ribbon: AXUIElement,
        title: String
    ) {
        for child in getChildren(ribbon) {
            guard let role = getAttribute(
                child,
                kAXRoleAttribute as String
            ) as? String,
            role == "AXRadioButton" else {
                continue
            }

            let tabTitle = getAttribute(
                child,
                kAXTitleAttribute as String
            ) as? String

            guard tabTitle == title else {
                continue
            }

            let error = AXUIElementPerformAction(
                child,
                kAXPressAction as CFString
            )

            print("Selected \(title): \(error.rawValue)")
            return
        }
    }

    
    private func inspectRibbonCommands(_ ribbon: AXUIElement) {
        print("\nRIBBON COMMANDS")
        print("===============")

        for child in getChildren(ribbon) {
            guard let role = getAttribute(
                child,
                kAXRoleAttribute as String
            ) as? String,
            role == "AXScrollArea" else {
                continue
            }

            inspect(element: child, depth: 0, maxDepth: 10)
        }
    }
    
    
    private func inspectAllRibbonTabs(_ ribbon: AXUIElement) {
        let children = getChildren(ribbon)

        for tab in children {
            guard let role = getAttribute(
                tab,
                kAXRoleAttribute as String
            ) as? String,
            role == "AXRadioButton" else {
                continue
            }

            let title = getAttribute(
                tab,
                kAXTitleAttribute as String
            ) as? String ?? "Unknown"

            print("\n\n================================")
            print("RIBBON TAB: \(title)")
            print("================================")

            let error = AXUIElementPerformAction(
                tab,
                kAXPressAction as CFString
            )

            guard error == .success else {
                print("Could not select tab: \(error.rawValue)")
                continue
            }

            // Aktuelle Ribbon-Kommandos auslesen
            inspectRibbonCommands(ribbon)
        }
    }

    
    private func inspectDetailed(_ element: AXUIElement, depth: Int = 0) {
        let indent = String(repeating: " ", count: depth * 2)

        let role = getAttribute(
            element,
            kAXRoleAttribute as String
        ) as? String ?? "?"

        let title = getAttribute(
            element,
            kAXTitleAttribute as String
        ) as? String ?? ""

        let description = getAttribute(
            element,
            kAXDescriptionAttribute as String
        ) as? String ?? ""

        let identifier = getAttribute(
            element,
            kAXIdentifierAttribute as String
        ) as? String ?? ""

        var actions: CFArray?

        AXUIElementCopyActionNames(element, &actions)

        let actionNames = actions as? [String] ?? []

        print("""
        \(indent)\(role)
        \(indent)  Title: \(title)
        \(indent)  Description: \(description)
        \(indent)  Identifier: \(identifier)
        \(indent)  Actions: \(actionNames)
        """)

        for child in getChildren(element) {
            inspectDetailed(child, depth: depth + 1)
        }
    }
    
    func inspectRibbon() {
        guard let excel = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.microsoft.Excel"
        ).first else {
            print("Excel is not running")
            return
        }

        let app = AXUIElementCreateApplication(
            excel.processIdentifier
        )

        var windowValue: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        guard error == .success,
              let windowValue else {
            print("Could not get focused Excel window")
            return
        }

        let window = windowValue as! AXUIElement

        let reader = RibbonReader()

        guard let ribbonElement = findRibbon(in: window),
              let ribbon = reader.readRibbon(ribbonElement) else {
            return
        }

        for tab in ribbon.tabs {
            print("\nTAB: \(tab.title)")

            for group in tab.groups {
                print("  GROUP: \(group.title ?? "Unknown")")

                for command in group.commands {
                    print("    COMMAND: \(command.title) [\(command.role)]")
                }
            }
        }
    }

 

}
