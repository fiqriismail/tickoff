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
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New project" : "Edit project").font(.title2.bold())

            field("Name") {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($nameFocused)
                    .onSubmit(save)
            }

            field("Colour") {
                HStack(spacing: 10) {
                    ForEach(Accent.allCases, id: \.self) { accent in
                        swatch(accent)
                    }
                }
            }

            field("Notes") {
                TextEditor(text: $draft.notes)
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

            if let error {
                Text(error).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }

    private func swatch(_ accent: Accent) -> some View {
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
