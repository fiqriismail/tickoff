import SwiftUI

/// The sidebar's PROJECTS section: an "All Projects" row and one row per project with its colour
/// dot and task count, a "+" in the header, and edit / archive / delete on each row's context
/// menu. It is a `Section` meant to sit inside the sidebar `List`, which owns the selection; rows
/// are tagged with `ProjectScope`. The shell presents the editor sheet, so this only asks for it.
struct ProjectsSection: View {
    let projects: [Project]
    let tasks: TaskSet
    let store: ProjectStore
    let report: (Outcome) -> Void
    /// Opens the editor: a project to edit, or `nil` for a new one.
    let edit: (Project?) -> Void

    @State private var deleting: Project?

    var body: some View {
        Section {
            Label("All Projects", systemImage: "square.stack.3d.up")
                .badge(tasks.count(nil))
                .tag(ProjectScope.all)
            ForEach(projects) { project in
                Label {
                    Text(project.name)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(project.colour.color)
                }
                .badge(tasks.count(nil, project: project.id))
                .tag(ProjectScope.project(project.id))
                .contextMenu { menu(for: project) }
            }
        } header: {
            HStack {
                Text("Projects")
                Spacer()
                Button("New Project", systemImage: "plus") { edit(nil) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("New project")
            }
        }
        .confirmationDialog(
            deleteTitle, isPresented: isDeleting, presenting: deleting
        ) { project in
            Button("Delete Project", role: .destructive) {
                report(Outcome.run { try store.delete(id: project.id) })
            }
        } message: { project in
            Text(deleteMessage(count: tasks.count(nil, project: project.id)))
        }
    }

    @ViewBuilder private func menu(for project: Project) -> some View {
        Button("Edit…") { edit(project) }
        if !project.isInbox {
            Button("Archive") {
                report(Outcome.run { try store.setArchived(id: project.id, true) })
            }
            Divider()
            Button("Delete…", role: .destructive) { deleting = project }
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var deleteTitle: String { "Delete “\(deleting?.name ?? "")”?" }

    private func deleteMessage(count: Int) -> String {
        count == 0
            ? "The project has no tasks."
            : "Its \(count) \(count == 1 ? "task" : "tasks") will be deleted permanently."
    }
}
