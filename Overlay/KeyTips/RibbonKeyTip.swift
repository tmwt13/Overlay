import CoreGraphics

struct RibbonKeyTip {
    enum Target {
        case tab(RibbonTab)
        case command(RibbonCommand, WindowsRibbonKeyTips.Activation)
    }

    let key: String
    let frame: CGRect
    let target: Target
}
