import AppKit
import SwiftUI

/// What the menu bar can ask the focused window to do. The window publishes these as a focused
/// value, so a command reaches the shell without any feature importing another.
struct AppActions {
    var newTask: () -> Void
    var find: () -> Void
}

extension FocusedValues {
    @Entry var appActions: AppActions?
}

/// The menu bar: New Task ⌘N, Find Tasks ⌘F, Hide/Show Sidebar ⌃⌘S and the About panel.
/// Settings ⌘, comes from the `Settings` scene, and the Edit and Window menus are the standard ones.
struct AppCommands: Commands {
    @FocusedValue(\.appActions) private var actions

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Task") { actions?.newTask() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Find Tasks") { actions?.find() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Tickoff") { Self.showAbout() }
        }
    }

    /// Name, version and copyright come from the bundle's Info.plist; the credits add the rest.
    private static func showAbout() {
        let credits = NSAttributedString(
            string: "A small task manager built with SwiftUI.\nMIT License.\nBuilt with Claude Code.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
            ])
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate()
    }
}
