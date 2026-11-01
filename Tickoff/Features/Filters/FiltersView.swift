import SwiftUI

/// The sidebar: shell-supplied project rows above the status filters (counted within the chosen
/// project), a progress summary and "Clear completed". It owns the `List`, so it also reconciles
/// the project and filter choices into the one selection the List reports.
struct FiltersView<Projects: View>: View {
    let tasks: TaskSet
    @Binding var scope: ProjectScope
    @Binding var filter: Filter
    @ViewBuilder let projects: () -> Projects
    let store: TaskStore
    let report: (Outcome) -> Void

    @State private var confirmingClear = false

    var body: some View {
        List(selection: selection) {
            projects()
            Section("Library") {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Label(filter.label, systemImage: filter.symbol)
                        .badge(tasks.count(filter.status, project: scope.projectID))
                        .tag(filter)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("\(done) of \(total) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { confirmingClear = true } label: {
                    Text("Clear Completed").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .controlSize(.large)
                    .disabled(done == 0)
                    .padding(.top, 6)
            }
            .padding(16)
        }
        .confirmationDialog(
            "Clear \(done) completed \(done == 1 ? "task" : "tasks")?",
            isPresented: $confirmingClear
        ) {
            Button("Clear Completed", role: .destructive) {
                report(Outcome.run { try store.clearCompleted() })
            }
        } message: {
            Text("They will be deleted permanently.")
        }
    }

    private var selection: Binding<Set<AnyHashable>> {
        Binding(
            get: { SidebarSelection.selection(scope: scope, filter: filter) },
            set: {
                let next = SidebarSelection.reconcile($0, scope: scope, filter: filter)
                scope = next.scope
                filter = next.filter
            })
    }

    private var total: Int { tasks.count(nil) }
    private var done: Int { tasks.count(.done) }
}
