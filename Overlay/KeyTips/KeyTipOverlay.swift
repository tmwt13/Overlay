import AppKit
import SwiftUI

struct KeyTipLabel {
    let text: String
    let frame: CGRect
}

final class KeyTipOverlay {
    private struct CanvasPanel {
        let panel: NSPanel
        let canvas: KeyTipCanvas
    }

    private var canvases: [NSNumber: CanvasPanel] = [:]
    private var detailPanel: NSPanel?

    func hide() {
        closeDetail()
        canvases.values.forEach { $0.panel.orderOut(nil) }
    }

    func show(_ labels: [KeyTipLabel], command: String? = nil) {
        let screens = NSScreen.screens
        guard let primary = screens.first else { hide(); return }

        if let command {
            hide()
            let screen = screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? primary
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

        closeDetail()
        var activeScreens: Set<NSNumber> = []
        var attachedScreens: Set<NSNumber> = []
        for screen in screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            attachedScreens.insert(id)
            let visible = labels.compactMap { label -> KeyTipCanvas.Label? in
                let center = CGPoint(x: label.frame.midX, y: primary.frame.maxY - label.frame.midY)
                guard screen.frame.contains(center) else { return nil }
                return KeyTipCanvas.Label(text: label.text, center: center)
            }
            guard !visible.isEmpty else { continue }
            activeScreens.insert(id)

            let bounds = visible.reduce(CGRect.null) { bounds, label in
                bounds.union(CGRect(x: label.center.x - 20, y: label.center.y - 12, width: 40, height: 24))
            }.integral.intersection(screen.frame)

            let entry: CanvasPanel
            if let existing = canvases[id] {
                entry = existing
            } else {
                let panel = makePanel(in: bounds)
                let canvas = KeyTipCanvas(frame: CGRect(origin: .zero, size: bounds.size))
                panel.contentView = canvas
                entry = CanvasPanel(panel: panel, canvas: canvas)
                canvases[id] = entry
            }

            if entry.panel.frame != bounds { entry.panel.setFrame(bounds, display: false) }
            entry.canvas.labels = visible.map { label in
                KeyTipCanvas.Label(text: label.text,
                    center: CGPoint(x: label.center.x - bounds.minX, y: label.center.y - bounds.minY))
            }
            if !entry.panel.isVisible { entry.panel.orderFrontRegardless() }
        }
        for (id, entry) in canvases where !activeScreens.contains(id) {
            entry.panel.orderOut(nil)
        }
        canvases = canvases.filter { attachedScreens.contains($0.key) }
    }

    func showTransientMessage(_ message: String) {
        show([], command: message)
        guard let panel = detailPanel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak panel] in
            guard let self, let panel, self.detailPanel === panel else { return }
            self.closeDetail()
        }
    }

    private func closeDetail() {
        detailPanel?.orderOut(nil)
        detailPanel = nil
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
        let panel = makePanel(in: bounds)
        panel.contentView = NSHostingView(rootView: content().frame(width: bounds.width, height: bounds.height))
        panel.orderFrontRegardless()
        detailPanel = panel
    }

    private func makePanel(in bounds: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}
