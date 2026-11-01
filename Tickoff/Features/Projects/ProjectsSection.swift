import SwiftUI

/// The sidebar's PROJECTS section: an "All Projects" row and one row per project with its colour
/// dot and task count. It is a `Section` meant to sit inside the sidebar `List`, which owns the
/// selection; rows are tagged with `ProjectScope` and the shell reads the choice from there.
struct ProjectsSection: View {
    let projects: [Project]
    let tasks: TaskSet

    var body: some View {
        Section("Projects") {
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
            }
        }
    }
}
