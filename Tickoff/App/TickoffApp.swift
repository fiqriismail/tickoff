import SwiftUI

@main
struct TickoffApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .applying(model.settings.appearance)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(model: model.settings)
                .applying(model.settings.appearance)
        }
        .windowResizability(.contentSize)
    }
}
