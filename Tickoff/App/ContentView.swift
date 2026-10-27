import SwiftUI

/// The shell layout: a hideable, resizable sidebar of filters and the task area as the detail.
/// It only routes; the sidebar's selection lives here so features never import each other.
struct ContentView: View {
    let model: AppModel
    @State private var filter: Filter = .all
    @State private var editing: Task?
    /// Bumped by menu commands; the features focus their field when it changes.
    @State private var newTaskRequest = 0
    @State private var findRequest = 0

    var body: some View {
        NavigationSplitView {
            FiltersView(
                tasks: model.tasks, selection: $filter, store: model.taskStore,
                report: model.handle
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            TaskListView(
                tasks: model.tasks, filter: filter, appearance: model.settings.appearance,
                store: model.taskStore, report: model.handle,
                searchRequest: findRequest,
                edit: { editing = $0 },
                accessory: {
                    AddTaskBar(
                        store: model.taskStore, report: model.handle, focusRequest: newTaskRequest)
                }
            )
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message, dismiss: model.dismissError)
                    }
                }
        }
        .sheet(item: $editing) { task in
            EditTaskView(task: task, store: model.taskStore, finish: model.handle)
        }
        .focusedSceneValue(
            \.appActions,
            AppActions(newTask: { newTaskRequest += 1 }, find: { findRequest += 1 })
        )
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    if let database = try? AppDatabase() {
        ContentView(model: AppModel(database: database))
    }
}
