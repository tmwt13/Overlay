import AppKit
import SwiftUI

struct KeyTipLabel {
    let text: String
    let frame: CGRect
}

final class KeyTipOverlay {
    private var panels: [NSPanel] = []

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    func show(_ labels: [KeyTipLabel], command: String? = nil) {
        hide()
        guard let primary = NSScreen.screens.first else { return }

        if let command {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? primary
            let bounds = screen.visibleFrame
            present(in: CGRect(x: bounds.midX - 195, y: bounds.minY + 24, width: 390, height: 38)) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            return
        }

        for screen in NSScreen.screens {
            let visible = labels.compactMap { label -> (String, CGPoint)? in
                let point = CGPoint(x: label.frame.midX, y: primary.frame.maxY - label.frame.midY)
                guard screen.frame.contains(point) else { return nil }
                return (label.text, point)
            }
            guard !visible.isEmpty else { continue }

            let bounds = visible.reduce(CGRect.null) { result, label in
                result.union(CGRect(x: label.1.x - 20, y: label.1.y - 12, width: 40, height: 24))
            }.intersection(screen.frame)

            present(in: bounds) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    ForEach(visible.indices, id: \.self) { index in
                        let (key, point) = visible[index]
                        Text(key.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 1, green: 0.91, blue: 0.64),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .position(x: point.x - bounds.minX, y: bounds.maxY - point.y)
                    }
                }
            }
        }
    }

    func showHelp(_ commands: [(usage: String, summary: String)]) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.screens.first else { return }
        let viewport = screen.visibleFrame
        let width = min(550, viewport.width - 32)
        let height = CGFloat(100 + commands.count * 24)
        let bounds = CGRect(x: viewport.midX - width / 2, y: viewport.midY - height / 2,
                            width: width, height: height)
        present(in: bounds) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Excel-Befehle").font(.headline)
                    Spacer()
                    Text("Esc zum Schließen").foregroundStyle(.secondary)
                }
                ForEach(commands.indices, id: \.self) { index in
                    let command = commands[index]
                    HStack {
                        Text(command.usage)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 150, alignment: .leading)
                        Text(command.summary)
                    }
                    .lineLimit(1)
                }
                Divider()
                Text("nnoremap ul <Cmd>call Excel('underline')<CR>")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func present<Content: View>(in bounds: CGRect, @ViewBuilder content: () -> Content) {
        let panel = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: content().frame(width: bounds.width, height: bounds.height))
        panel.orderFrontRegardless()
        panels.append(panel)
    }
}
