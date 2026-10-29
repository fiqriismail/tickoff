import SwiftUI

/// The sidebar: status filters with live counts, a progress summary and "Clear completed".
struct FiltersView: View {
    let tasks: TaskSet
    @Binding var selection: Filter
    let store: TaskStore
    let report: (Outcome) -> Void

    @State private var confirmingClear = false

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Label(filter.label, systemImage: filter.symbol)
                        .badge(tasks.count(filter.status))
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

    private var total: Int { tasks.count(nil) }
    private var done: Int { tasks.count(.done) }
}
