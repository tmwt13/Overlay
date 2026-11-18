import ApplicationServices

enum AX {
    static func application(_ process: pid_t, timeout: Float) -> AXUIElement {
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func attributes(_ names: [String], of element: AXUIElement) -> [String: CFTypeRef] {
        var raw: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &raw)
        if result == .success, let values = raw as? [CFTypeRef], values.count == names.count {
            return Dictionary(uniqueKeysWithValues: zip(names, values))
        }
        guard result == .notImplemented || result == .illegalArgument else { return [:] }
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            attribute(name, of: element).map { (name, $0) }
        })
    }

    static func element(_ name: String, of parent: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: parent),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        return element
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    static func string(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    static func boolean(_ name: String, of element: AXUIElement) -> Bool? {
        (attribute(name, of: element) as? NSNumber)?.boolValue
    }

    static func role(of element: AXUIElement) -> String? {
        string(kAXRoleAttribute, of: element)
    }

    static func perform(_ action: String, on element: AXUIElement) -> Bool {
        actionResult(action, on: element) == .success
    }

    static func actionResult(_ action: String, on element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }

    static func press(_ element: AXUIElement) -> Bool {
        perform(kAXPressAction, on: element)
    }

    static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    static func actions(of element: AXUIElement) -> [String] {
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        return actions as? [String] ?? []
    }

    static func frame(in attributes: [String: CFTypeRef]) -> CGRect? {
        guard let position = attributes[kAXPositionAttribute],
              let size = attributes[kAXSizeAttribute],
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
