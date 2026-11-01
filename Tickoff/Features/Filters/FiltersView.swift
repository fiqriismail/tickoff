import SwiftUI

/// The sidebar: shell-supplied project rows above the status filters (counted within the chosen
/// project), and a progress summary and "Clear completed" for that same project. It owns the `List`, so it also reconciles
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
                        .tag(AnyHashable(filter))
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
                report(Outcome.run { try store.clearCompleted(project: scope.projectID) })
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

    // Progress follows the chosen project, so it always matches the counts above it.
    private var total: Int { tasks.count(nil, project: scope.projectID) }
    private var done: Int { tasks.count(.done, project: scope.projectID) }
}
