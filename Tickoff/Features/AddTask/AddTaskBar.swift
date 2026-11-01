import SwiftUI

/// The quick-add bar above the task list: a title, a project and a priority; Enter adds a To do
/// task. The project starts on the shell's default (the selected project, else Inbox) and goes
/// back to it after each add. The project menu only shows under All Projects, where the choice
/// matters; inside one project the placeholder names it instead.
struct AddTaskBar: View {
    let store: TaskStore
    /// The projects that can be chosen (not archived), supplied by the shell.
    let projects: [Project]
    /// Last-used project ids, most recent first, for the menu's Recent section.
    let recentProjectIDs: [Int64]
    let defaultProjectID: Int64
    /// False when the list is already one project, which makes the choice redundant.
    let offersProjectChoice: Bool
    let report: (Outcome) -> Void
    /// Tells the shell which project just received a task.
    let used: (Int64) -> Void
    /// Changes when the shell wants the title field focused (New Task).
    let focusRequest: Int

    @State private var title = ""
    @State private var priority: Priority = .medium
    @State private var chosenProjectID: Int64?
    @FocusState private var focused: Bool

    /// The default until the user picks another; also covers a chosen project that was archived.
    private var projectID: Int64 {
        let id = chosenProjectID ?? defaultProjectID
        return projects.contains { $0.id == id } ? id : defaultProjectID
    }

    private var project: Project? { projects.first { $0.id == projectID } }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(add)
                .onChange(of: focusRequest) { focused = true }

            if offersProjectChoice { projectMenu }

            Picker("Priority", selection: $priority) {
                ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            Button("Add", systemImage: "plus", action: add)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        // Selecting another project in the sidebar changes where tasks go by default.
        .onChange(of: defaultProjectID) { chosenProjectID = nil }
    }

    private var placeholder: String {
        project.map { "Add a task to \($0.name) and press Return" } ?? "Add a task and press Return"
    }

    /// Capped width, so a long project name can't push Priority and Add off the bar.
    private var projectMenu: some View {
        let sections = ProjectMenuSections(projects: projects, recentIDs: recentProjectIDs)
        return Menu {
            if let inbox = sections.inbox { item(inbox) }
            if !sections.recent.isEmpty {
                Section("Recent") { ForEach(sections.recent) { item($0) } }
            }
            if !sections.all.isEmpty {
                Section("All Projects") { ForEach(sections.all) { item($0) } }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(project?.colour.color ?? .secondary)
                    .imageScale(.small)
                Text(project?.name ?? "Project").lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: 150)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Project for the new task")
        .accessibilityLabel("Project: \(project?.name ?? "none")")
    }

    private func item(_ project: Project) -> some View {
        Button {
            chosenProjectID = project.id
        } label: {
            if project.id == projectID {
                Label(project.name, systemImage: "checkmark")
            } else {
                Text(project.name)
            }
        }
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = projectID
        let outcome = Outcome.run {
            try store.insert(title: trimmed, priority: priority, projectID: target)
        }
        if outcome == .changed {
            title = ""
            chosenProjectID = nil
            used(target)
        }
        report(outcome)
        focused = true
    }
}
