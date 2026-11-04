import SwiftUI

/// The sidebar's PROJECTS section: an "All Projects" row and one row per project with its colour
/// dot and task count, a "+" in the header, and edit / archive / delete on each row's context
/// menu. It is a `Section` meant to sit inside the sidebar `List`, which owns the selection; rows
/// are tagged with `ProjectScope` boxed as `AnyHashable`, because the List's selection is a
/// `Set<AnyHashable>` and SwiftUI only matches a tag whose type equals the selection's element type.
/// The shell presents the editor sheet, so this only asks for it.
struct ProjectsSection: View {
    let projects: [Project]
    let tasks: TaskSet
    let store: ProjectStore
    let report: (Outcome) -> Void
    /// Opens the editor: a project to edit, or `nil` for a new one.
    let edit: (Project?) -> Void
    var goalBadges: [Int64: String] = [:]

    @State private var deleting: Project?

    var body: some View {
        Section {
            Label("All Projects", systemImage: "square.stack.3d.up")
                .padding(.vertical, 2)
                .badge(tasks.count(nil))
                .tag(AnyHashable(ProjectScope.all))
            ForEach(projects) { project in
                Label {
                    Text(project.name)
                } icon: {
                    Image(systemName: project.kind == .dailyGoals ? "target" : "circle.fill")
                        .foregroundStyle(project.colour.color)
                }
                .padding(.vertical, 2)
                .badge(badge(for: project))
                .tag(AnyHashable(ProjectScope.project(project.id)))
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
                    // Lines the plus up with the count badges instead of the sidebar's edge.
                    .padding(.trailing, 14)
            }
            .padding(.bottom, 2)
        }
        .confirmationDialog(
            deleteTitle, isPresented: isDeleting, presenting: deleting
        ) { project in
            Button("Delete Project", role: .destructive) {
                report(Outcome.run { try store.delete(id: project.id) })
            }
        } message: { project in
            Text(project.kind == .dailyGoals
                ? "Its goals will be removed from Today. Recorded history will be kept."
                : deleteMessage(count: tasks.count(nil, project: project.id)))
        }
    }

    private func badge(for project: Project) -> Text? {
        if project.kind == .dailyGoals {
            return Text(goalBadges[project.id] ?? "0/0")
        }
        let count = tasks.count(nil, project: project.id)
        return count == 0 ? nil : Text(count.formatted())
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
