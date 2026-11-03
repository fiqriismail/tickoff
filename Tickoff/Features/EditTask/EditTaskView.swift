import SwiftUI

/// The "Edit task" sheet. Enter in the title saves, Esc cancels, and a failure shows inline.
/// The shell presents it and gets the `Outcome` back; this feature never reloads anything itself.
struct EditTaskView: View {
    let store: TaskStore
    /// The projects the task can be moved to, supplied by the shell.
    let projects: [Project]
    let finish: (Outcome) -> Void

    @State private var draft: TaskDraft
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        task: Task, store: TaskStore, projects: [Project], finish: @escaping (Outcome) -> Void
    ) {
        self.store = store
        self.projects = projects
        self.finish = finish
        _draft = State(initialValue: TaskDraft(task: task))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Task").font(.title2)

            // The columns style puts right-aligned labels in a leading column, controls in the second.
            Form {
                // Each row gets its own breathing room; the columns style packs them tightly.
                Group {
                    TextField("Title", text: $draft.title)
                        .focused($titleFocused)
                        .onSubmit(save)

                    LabeledContent("Notes") {
                        TextEditor(text: $draft.notes)
                            .font(.body)
                            .frame(height: 90)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                            // Line the "Notes" label up with the first line of text, like the other rows.
                            .alignmentGuide(.firstTextBaseline) { $0[.top] + 16.5 }
                    }

                    Picker("Status", selection: $draft.status) {
                        ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .fixedSize()

                    Picker("Priority", selection: $draft.priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .fixedSize()

                    Picker("Project", selection: $draft.projectID) {
                        ForEach(projects) { Text($0.name).tag($0.id) }
                    }
                    .fixedSize()

                    LabeledContent("Due") {
                        HStack {
                            Toggle("Due date", isOn: $draft.hasDue)
                            DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                                .labelsHidden()
                                .disabled(!draft.hasDue)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .formStyle(.columns)

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
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { titleFocused = true }
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
