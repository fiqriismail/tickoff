import SwiftUI

@main
struct TickoffApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .applying(model.settings.appearance)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { SidebarCommands() }

        Settings {
            SettingsView(model: model.settings)
                .applying(model.settings.appearance)
        }
        .windowResizability(.contentSize)
    }
}
