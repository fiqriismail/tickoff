import SwiftUI

/// The "New project" / "Edit project" sheet: name, colour, notes and (when editing) the archived
/// flag. Validation errors, including duplicate names, show inline and keep the sheet open.
struct ProjectEditorView: View {
    let store: ProjectStore
    let finish: (Outcome) -> Void

    @State private var draft: ProjectDraft
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Pass `nil` to create a project.
    init(project: Project?, store: ProjectStore, finish: @escaping (Outcome) -> Void) {
        self.store = store
        self.finish = finish
        _draft = State(initialValue: project.map(ProjectDraft.init(project:)) ?? ProjectDraft())
    }

    private var isNew: Bool { draft.id == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Project" : "Edit Project").font(.title2)

            // The columns style puts right-aligned labels in a leading column, controls in the second.
            Form {
                TextField("Name", text: $draft.name, prompt: Text("Required"))
                    .focused($nameFocused)
                    .onSubmit(save)

                LabeledContent("Colour") {
                    HStack(spacing: 6) {
                        ForEach(ProjectColour.allCases, id: \.self) { colour in
                            swatch(colour)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Colour")
                }

                LabeledContent("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                }

                if !isNew && !draft.isInbox {
                    Toggle("Archived", isOn: $draft.archived)
                        .help("Archived projects are hidden from the sidebar; their tasks still show under All Projects.")
                }
            }
            .formStyle(.columns)

            if let error {
                Text(error).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }

    /// A radio-style swatch: ringed and marked selected when chosen, always labelled for VoiceOver.
    private func swatch(_ accent: ProjectColour) -> some View {
        Button { draft.colour = accent } label: {
            Circle().fill(accent.color).frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.primary, lineWidth: draft.colour == accent ? 2 : 0).padding(-4))
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(accent.label)
        .accessibilityLabel(accent.label)
        .accessibilityAddTraits(draft.colour == accent ? .isSelected : [])
    }

    private func save() {
        do {
            let project = try draft.validated()
            if draft.id == nil {
                try store.create(name: project.name, colour: project.colour, notes: project.notes)
            } else {
                try store.update(project)
                if !project.isInbox { try store.setArchived(id: project.id, project.archived) }
            }
            finish(.changed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
