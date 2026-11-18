import AppKit
import SwiftUI

struct OverlayMenu: View {
    @ObservedObject var controller: KeyTipController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Excel KeyTips").font(.headline)
                    Label {
                        Text(statusText).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: statusIcon)
                            .foregroundStyle(controller.keyboardAccess == .ready ? Color.green : Color.orange)
                    }
                    .font(.caption)
                }
            }

            if controller.keyboardAccess != .ready {
                Button(accessButtonTitle) { controller.enable(prompt: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Vim in Excel", isOn: $controller.vimEnabled)
                    .toggleStyle(MenuSwitchStyle())
                if controller.vimEnabled {
                    if controller.vimStatus.isEmpty {
                        HStack(spacing: 6) {
                            Text("Modus").foregroundStyle(.secondary)
                            Text(controller.vimMode.rawValue)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(modeColor.opacity(0.12), in: Capsule())
                        }
                        .font(.caption)
                    } else {
                        Text(controller.vimStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 7) {
                shortcut("KeyTips öffnen", keys: "⌥")
                if controller.vimEnabled {
                    shortcut("Excel-Befehle anzeigen", keys: ":help excel")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Label("Beenden", systemImage: "power")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 294)
    }

    private var modeColor: Color {
        switch controller.vimMode {
        case .insert: .blue
        case .normal: .green
        case .visual: .purple
        }
    }

    private var statusText: String {
        switch controller.keyboardAccess {
        case .needsPermission: "Bedienungshilfen-Zugriff fehlt"
        case .unavailable: "Tastaturzugriff nicht verfügbar"
        case .alreadyRunning: "Eine andere Overlay-Instanz ist aktiv"
        case .ready: "Bereit für Excel"
        }
    }

    private var statusIcon: String {
        controller.keyboardAccess == .ready ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var accessButtonTitle: String {
        controller.keyboardAccess == .needsPermission ? "Zugriff erlauben" : "Erneut versuchen"
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.background, in: RoundedRectangle(cornerRadius: 4))
        }
        .font(.caption)
    }
}

private struct MenuSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.35))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .padding(.horizontal, 2)
                    }
                    .frame(width: 32, height: 18)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}
