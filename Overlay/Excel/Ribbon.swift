import ApplicationServices

struct RibbonTab {
    let title: String
    let element: AXUIElement
    let frame: CGRect?
}

struct RibbonCommand {
    let title: String
    let identifier: String?
    let role: String?
    let actions: [String]
    let element: AXUIElement
    let frame: CGRect

    var supportsPress: Bool { actions.contains(kAXPressAction) }
}
