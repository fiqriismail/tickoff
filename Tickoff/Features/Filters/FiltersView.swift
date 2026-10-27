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

            Section("Progress") {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                    Text("\(done) of \(total) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if done > 0 {
                Button("Clear completed", role: .destructive) { confirmingClear = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], 12)
                    .buttonStyle(.link)
            }
        }
        .confirmationDialog(
            "Clear \(done) completed \(done == 1 ? "task" : "tasks")?",
            isPresented: $confirmingClear
        ) {
            Button("Clear completed", role: .destructive) {
                report(Outcome.run { try store.clearCompleted() })
            }
        } message: {
            Text("They will be deleted permanently.")
        }
    }

    private var total: Int { tasks.count(nil) }
    private var done: Int { tasks.count(.done) }
}
