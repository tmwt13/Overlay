import AppKit
import SwiftUI

final class VimModeIndicator {
    private let size: CGFloat = 22
    private var panel: IndicatorPanel?
    private var displayed: Presentation?
    private var anchor: CGRect?
    private var recordingRegister: String?
    private var notice: String?
    private var noticeID = UUID()

    private struct Presentation: Equatable {
        let mode: ExcelVim.Mode
        let recording: Bool
        let notice: String?
    }

    func show(_ mode: ExcelVim.Mode, recording register: String?, in quartzWindow: CGRect) {
        let screens = NSScreen.screens
        guard let primary = screens.first else { hide(); return }

        let window = CGRect(x: quartzWindow.minX, y: primary.frame.maxY - quartzWindow.maxY,
                            width: quartzWindow.width, height: quartzWindow.height)
        let visible = screens.map { window.intersection($0.visibleFrame) }.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
        guard let visible, !visible.isEmpty, visible.width >= size + 20,
              visible.height >= size + 42 else { hide(); return }

        anchor = visible
        if recordingRegister != register {
            recordingRegister = register
            noticeID = UUID()
            notice = register.map { "Aufnahme @\($0)" }
            if notice != nil {
                let id = noticeID
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, self.noticeID == id, let displayed = self.displayed else { return }
                    self.notice = nil
                    self.present(mode: displayed.mode)
                }
            }
        }
        present(mode: mode)
    }

    func hide() {
        anchor = nil
        notice = nil
        noticeID = UUID()
        panel?.orderOut(nil)
    }

    private func present(mode: ExcelVim.Mode) {
        guard let anchor else { return }
        let notice = anchor.width >= 150 ? notice : nil
        let frame = CGRect(x: anchor.minX + 10, y: anchor.minY + 32,
                           width: notice == nil ? size : 140, height: size)
        let panel = panel ?? makePanel(in: frame)
        let presentation = Presentation(mode: mode, recording: recordingRegister != nil, notice: notice)
        if displayed != presentation {
            panel.contentView = NSHostingView(rootView: VimModeBadge(
                mode: mode, size: size, recording: presentation.recording, notice: notice
            ))
            displayed = presentation
        }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel(in frame: CGRect) -> IndicatorPanel {
        let panel = IndicatorPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

private final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct VimModeBadge: View {
    let mode: ExcelVim.Mode
    let size: CGFloat
    let recording: Bool
    let notice: String?

    private var tint: Color {
        switch mode {
        case .normal: Color(red: 0.10, green: 0.37, blue: 0.23)
        case .insert: Color(red: 0.15, green: 0.31, blue: 0.63)
        case .visual: Color(red: 0.37, green: 0.23, blue: 0.59)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(String(mode.rawValue.prefix(1)))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if recording {
                        Circle().fill(.red)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                            .frame(width: 7, height: 7)
                            .padding(1)
                    }
                }

            if let notice {
                Text(notice)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: size)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.55, green: 0.15, blue: 0.17), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(recording ? "Vim-Modus \(mode.rawValue), Makroaufnahme"
                                      : "Vim-Modus \(mode.rawValue)")
    }
}
