import SwiftUI

/// The shell layout: a hideable, resizable sidebar of filters and the task area as the detail.
/// It only routes; the sidebar's selection lives here so features never import each other.
struct ContentView: View {
    let model: AppModel
    @State private var filter: Filter = .all
    @State private var editing: Task?

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
                edit: { editing = $0 },
                accessory: { AddTaskBar(store: model.taskStore, report: model.handle) }
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
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    if let database = try? AppDatabase() {
        ContentView(model: AppModel(database: database))
    }
}
