import SwiftUI

/// The "Edit task" sheet. Enter in the title saves, Esc cancels, and a failure shows inline.
/// The shell presents it and gets the `Outcome` back; this feature never reloads anything itself.
struct EditTaskView: View {
    let store: TaskStore
    let finish: (Outcome) -> Void

    @State private var draft: TaskDraft
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(task: Task, store: TaskStore, finish: @escaping (Outcome) -> Void) {
        self.store = store
        self.finish = finish
        _draft = State(initialValue: TaskDraft(task: task))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit task").font(.title2.bold())

            field("Title") {
                TextField("Title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($titleFocused)
                    .onSubmit(save)
            }

            field("Notes") {
                TextEditor(text: $draft.notes)
                    .frame(height: 90)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            }

            HStack(alignment: .top, spacing: 16) {
                field("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                field("Priority") {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
            }

            field("Due date") {
                HStack {
                    Toggle("Due date", isOn: $draft.hasDue).labelsHidden()
                    DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .disabled(!draft.hasDue)
                    if !draft.hasDue { Text("No due date").foregroundStyle(.secondary) }
                }
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { titleFocused = true }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        do {
            let task = try draft.validated()
            try store.update(task)
            finish(.changed)
            dismiss()
        } catch let invalid as TaskDraft.ValidationError {
            error = invalid.message
        } catch {
            self.error = "Could not save: \(error.localizedDescription)"
        }
    }
}
