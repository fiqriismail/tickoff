import SwiftUI

/// Creates or edits a goal template; existing daily snapshots are never changed by this sheet.
struct GoalEditorView: View {
    let projectID: Int64
    let store: DailyGoalStore
    let finish: (Outcome) -> Void
    @State private var draft: GoalDraft
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(projectID: Int64, goal: DailyGoal?, store: DailyGoalStore, finish: @escaping (Outcome) -> Void) {
        self.projectID = projectID
        self.store = store
        self.finish = finish
        _draft = State(initialValue: GoalDraft(goal: goal))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.id == nil ? "New Goal" : "Edit Goal").font(.title2)
            Form {
                Group {
                    TextField("Name", text: $draft.name)
                        .focused($nameFocused)
                        .onSubmit(save)
                    Picker("Tracking", selection: $draft.tracking) {
                        ForEach(GoalTracking.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    if draft.tracking == .counter {
                        TextField("Daily target", text: $draft.target)
                            .onSubmit(save)
                    }
                }
                .padding(.vertical, 4)
            }
            .formStyle(.columns)
            if draft.id != nil {
                Text("Changes apply tomorrow. Today's goal and progress stay unchanged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.id == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }

    private func save() {
        do {
            let goal = try draft.validated(projectID: projectID)
            if draft.id == nil {
                try store.create(
                    projectID: projectID, name: goal.name, tracking: goal.tracking, target: goal.target)
            } else {
                try store.update(goal)
            }
            finish(.changed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
