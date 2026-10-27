import AppKit
import SwiftUI

/// Tickoff is a single-window app, so closing the window quits it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TickoffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.launch()

    var body: some Scene {
        Window("Tickoff", id: "main") {
            ContentView(model: model)
                .applying(model.settings.appearance)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands() }

        Settings {
            SettingsView(model: model.settings)
                .applying(model.settings.appearance)
        }
        .windowResizability(.contentSize)
    }
}
