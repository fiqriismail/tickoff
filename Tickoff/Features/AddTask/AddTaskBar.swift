import SwiftUI

/// The quick-add bar above the task list: a title and a priority; Enter adds a To do task.
struct AddTaskBar: View {
    let store: TaskStore
    let report: (Outcome) -> Void
    /// Changes when the shell wants the title field focused (New Task).
    let focusRequest: Int

    @State private var title = ""
    @State private var priority: Priority = .medium
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Add a task and press Enter…", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(add)
                .onChange(of: focusRequest) { focused = true }

            Picker("Priority", selection: $priority) {
                ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            Button("Add", systemImage: "plus", action: add)
                .buttonStyle(.borderedProminent)
        }
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let outcome = Outcome.run { try store.insert(title: trimmed, priority: priority) }
        if outcome == .changed { title = "" }
        report(outcome)
        focused = true
    }
}
