import SwiftUI

@main struct MyApp: App {
    @StateObject private var controller = KeyTipController()

    var body: some Scene {
        MenuBarExtra("Excel KeyTips", systemImage: "keyboard") {
            Text(controller.status)
            Button("Tastaturzugriff aktivieren") {
                controller.enable(prompt: true)
            }
            Divider()
            Toggle("Excel-Vim", isOn: $controller.vimEnabled)
            if controller.vimEnabled {
                Text(controller.vimStatus.isEmpty
                     ? "Modus: \(controller.vimMode.rawValue)" : controller.vimStatus)
            }
            Divider()
            Button("Beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .defaultLaunchBehavior(.presented)
    }
}
