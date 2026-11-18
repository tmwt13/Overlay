import SwiftUI

@main
struct OverlayApp: App {
    @StateObject private var controller = KeyTipController()

    var body: some Scene {
        MenuBarExtra {
            OverlayMenu(controller: controller)
        } label: {
            if controller.isExcelFrontmost, controller.vimEnabled, controller.vimStatus.isEmpty,
               controller.keyboardAccess == .ready {
                Label(controller.vimMode.rawValue.uppercased(), systemImage: "keyboard")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("Excel KeyTips, Vim-Modus \(controller.vimMode.rawValue)")
            } else {
                Image(systemName: "keyboard")
                    .accessibilityLabel("Excel KeyTips")
            }
        }
        .menuBarExtraStyle(.window)
        .defaultLaunchBehavior(.presented)
    }
}
