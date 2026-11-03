import SwiftUI

/// What the menu bar can do to the selected task. `TaskListView` publishes it as a focused scene
/// value only while a row is selected, so the commands are disabled otherwise and the shell never
/// has to know which row that is.
struct TaskActions {
    var status: Status
    var edit: () -> Void
    var setStatus: (Status) -> Void
    var delete: () -> Void
}

extension FocusedValues {
    @Entry var taskActions: TaskActions?
}
