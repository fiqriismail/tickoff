import AppKit
import SwiftUI

/// What the menu bar can ask the focused window to do. The window publishes these as a focused
/// value, so a command reaches the shell without any feature importing another.
struct AppActions {
    var newTask: () -> Void
    var newProject: () -> Void
    var find: () -> Void
    var clearCompleted: () -> Void
    /// Whether the chosen project has completed tasks to clear.
    var canClearCompleted: Bool
    var showNotes: Bool
    var compactRows: Bool
    var setShowNotes: (Bool) -> Void
    var setCompactRows: (Bool) -> Void
}

extension FocusedValues {
    @Entry var appActions: AppActions?
}

/// The menu bar: New Task ⌘N, New Project ⇧⌘N, Clear Completed…, the Task menu (Edit ⌘E, Mark As, Delete ⌘⌫), Find Tasks ⌘F, the Show Notes and
/// Compact Rows toggles, Hide/Show Sidebar ⌃⌘S and the About panel. Every toolbar item has a command here.
/// There is no Settings window: display options live in the View menu and the toolbar. The Edit and
/// Window menus are the standard ones.
struct AppCommands: Commands {
    @FocusedValue(\.appActions) private var actions
    @FocusedValue(\.taskActions) private var task

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Task") { actions?.newTask() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Button("New Project…") { actions?.newProject() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
            Button("Clear Completed…") { actions?.clearCompleted() }
                .disabled(actions?.canClearCompleted != true)
        }

        CommandMenu("Task") {
            Button("Edit Task…") { task?.edit() }
                .keyboardShortcut("e")
                .disabled(task == nil)
            Menu("Mark As") {
                ForEach(Status.allCases, id: \.self) { status in
                    Button(status.label) { task?.setStatus(status) }
                        .disabled(task == nil || task?.status == status)
                }
            }
            Divider()
            // ⌘⌫ rather than a bare Delete, which would also fire while typing in a text field.
            Button("Delete") { task?.delete() }
                .keyboardShortcut(.delete)
                .disabled(task == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Find Tasks") { actions?.find() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
            Divider()
            Toggle("Show Notes", isOn: Binding(
                get: { actions?.showNotes ?? true }, set: { actions?.setShowNotes($0) }))
                .disabled(actions == nil)
            Toggle("Use Compact Rows", isOn: Binding(
                get: { actions?.compactRows ?? false }, set: { actions?.setCompactRows($0) }))
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
