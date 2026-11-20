import AppKit
import SwiftUI

/// Tickoff is a single-window app, so closing the window quits it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // THROWAWAY (issue #67): headless measurement run, see `Spike/SpikeHarness.swift`.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let spec = ProcessInfo.processInfo.environment["TICKOFF_SPIKE"] else { return }
        if #available(macOS 27.0, *) {
            _Concurrency.Task {
                await SpikeHarness.run(spec: spec)
                exit(0)
            }
        }
    }
}

@main
struct TickoffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.launch()

    var body: some Scene {
        Window("Tickoff", id: "main") {
            ContentView(model: model)
        }
        .windowToolbarStyle(.unified)
        .commands { AppCommands() }
    }
}
