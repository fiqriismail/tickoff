import SwiftUI

/// The detail column: the toolbar (title, progress, search, More menu) and a lazily built list of
/// task cards. It holds no task data of its own; the shell's `TaskSet` is passed in.
struct TaskListView<Accessory: View>: View {
    let tasks: TaskSet
    let filter: Filter
    let scope: ProjectScope
    /// Every project, archived ones included: an archived project's tasks still show under All.
    let projects: [Project]
    let appearance: Appearance
    let store: TaskStore
    let report: (Outcome) -> Void
    /// Changes when the shell wants the search field focused (Find).
    let searchRequest: Int
    /// Changes when the shell wants the Clear Completed confirmation (menu command).
    let clearRequest: Int
    /// Applies a change to the display options (Show Notes, Compact Rows); the shell saves it.
    let updateAppearance: ((inout Appearance) -> Void) -> Void
    /// Opens the edit dialog; the shell decides what that means.
    let edit: (Task) -> Void
    /// Shell-supplied content shown between the header and the list (the quick-add bar).
    @ViewBuilder let accessory: () -> Accessory

    /// The content margin; header, add bar and cards all align to it.
    private static var margin: CGFloat { 16 }
    /// The side padding `List` adds around every row itself, subtracted so cards line up with the header.
    private static var listRowSideInset: CGFloat { 10 }

    @State private var query = ""
    @State private var cache = VisibleCache()
    @State private var searchPresented = false
    @State private var confirmingClear = false

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let visible = cache.tasks(
            in: tasks, status: filter.status, project: scope.projectID, query: query)
        VStack(spacing: 0) {
            accessory()
                .padding(.horizontal, Self.margin)
                .padding(.vertical, 12)
            if visible.isEmpty {
                // Fills the rest so the add bar stays pinned under the toolbar.
                emptyState.frame(maxHeight: .infinity)
            } else {
                list(visible)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Title, progress, search and More live in the window toolbar, like System Settings.
        .navigationTitle(scopedProject?.name ?? filter.label)
        .navigationSubtitle(
            ProgressSummary.text(
                done: tasks.count(.done, project: scope.projectID),
                total: tasks.count(nil, project: scope.projectID)))
        .searchable(text: $query, isPresented: $searchPresented, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
        .confirmationDialog(
            "Clear \(doneCount) completed \(doneCount == 1 ? "task" : "tasks")?",
            isPresented: $confirmingClear
        ) {
            Button("Clear Completed", role: .destructive) {
                report(Outcome.run { try store.clearCompleted(project: scope.projectID) })
            }
        } message: {
            Text("They will be deleted permanently.")
        }
        .onChange(of: searchRequest) { searchPresented = true }
        .onChange(of: clearRequest) { if doneCount > 0 { confirmingClear = true } }
    }

    private var doneCount: Int { tasks.count(.done, project: scope.projectID) }

    /// Every toolbar item also exists in the menu bar (View and File menus, via `AppActions`).
    private var moreMenu: some View {
        Menu {
            Toggle("Show Notes", isOn: Binding(
                get: { appearance.showNotes }, set: { value in updateAppearance { $0.showNotes = value } }))
            Toggle("Use Compact Rows", isOn: Binding(
                get: { appearance.compactCards }, set: { value in updateAppearance { $0.compactCards = value } }))
            Divider()
            Button("Clear Completed…") { confirmingClear = true }
                .disabled(doneCount == 0)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
    }

    private var scopedProject: Project? {
        scope.projectID.flatMap { id in projects.first { $0.id == id } }
    }

    /// Cards name their project only when the list spans all of them.
    private var projectsByID: [Int64: Project]? {
        scope == .all ? Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }) : nil
    }

    /// A `List` is backed by a recycling table, so only the rows on screen exist however many tasks
    /// there are.
    private func list(_ visible: [Task]) -> some View {
        let projectsByID = projectsByID
        return List(visible) { task in
            TaskCard(
                task: task, appearance: appearance,
                project: projectsByID?[task.projectID],
                setStatus: { status in
                    report(Outcome.run { try store.setStatus(id: task.id, to: status) })
                },
                edit: { edit(task) },
                delete: { report(Outcome.run { try store.delete(id: task.id) }) }
            )
            .listRowInsets(
                EdgeInsets(
                    top: appearance.compactCards ? 3 : 5, leading: Self.margin - Self.listRowSideInset,
                    bottom: appearance.compactCards ? 3 : 5, trailing: Self.margin - Self.listRowSideInset)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var emptyState: some View {
        if searching {
            ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if tasks.count(nil, project: scope.projectID) == 0 {
            ContentUnavailableView(
                scopedProject == nil ? "No tasks yet" : "No tasks in \(scopedProject?.name ?? "")",
                systemImage: "checklist",
                description: Text("Add your first one to get started."))
        } else if let project = scopedProject {
            ContentUnavailableView(
                "Nothing here yet", systemImage: "party.popper",
                description: Text("No \(filter.label.lowercased()) tasks in \(project.name)."))
        } else {
            ContentUnavailableView("Nothing here yet", systemImage: "party.popper")
        }
    }
}

/// Remembers the filtered list between view updates, keyed on what it was computed from, so typing
/// elsewhere or hovering never re-scans thousands of tasks. Plain class: it is not observed.
private final class VisibleCache {
    private var key: Key?
    private var result: [Task] = []

    private struct Key: Equatable {
        var revision: Int
        var status: Status?
        var project: Int64?
        var query: String
    }

    func tasks(in set: TaskSet, status: Status?, project: Int64?, query: String) -> [Task] {
        let wanted = Key(revision: set.revision, status: status, project: project, query: query)
        if wanted != key {
            result = set.visible(status: status, project: project, query: query)
            key = wanted
        }
        return result
    }
}
