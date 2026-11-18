import AppKit

final class KeyTipCanvas: NSView {
    struct Label {
        let text: String
        let center: CGPoint
    }

    var labels: [Label] = [] {
        didSet { needsDisplay = true }
    }

    private let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.black
    ]
    private let background = NSColor(calibratedRed: 1, green: 0.91, blue: 0.64, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        for label in labels {
            let title = label.text.uppercased() as NSString
            let size = title.size(withAttributes: textAttributes)
            let textRect = CGRect(x: label.center.x - size.width / 2,
                                  y: label.center.y - size.height / 2,
                                  width: size.width, height: size.height)
            let badge = textRect.insetBy(dx: -5, dy: -2)
            guard badge.intersects(dirtyRect) else { continue }
            background.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
            title.draw(in: textRect, withAttributes: textAttributes)
        }
    }
}
