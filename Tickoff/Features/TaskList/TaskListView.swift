import SwiftUI

/// The detail column: a header with the filter name and count, a search field (⌘F), and a lazily
/// built list of task cards. It holds no task data of its own; the shell's `TaskSet` is passed in.
struct TaskListView<Accessory: View>: View {
    let tasks: TaskSet
    let filter: Filter
    let appearance: Appearance
    let store: TaskStore
    let report: (Outcome) -> Void
    /// Changes when the shell wants the search field focused (Find).
    let searchRequest: Int
    /// Opens the edit dialog; the shell decides what that means.
    let edit: (Task) -> Void
    /// Shell-supplied content shown between the header and the list (the quick-add bar).
    @ViewBuilder let accessory: () -> Accessory

    /// The standard macOS content margin; header, add bar and cards all align to it.
    private static var margin: CGFloat { 20 }
    /// The side padding `List` adds around every row itself, subtracted so cards line up with the header.
    private static var listRowSideInset: CGFloat { 10 }

    @State private var query = ""
    @State private var cache = VisibleCache()
    @FocusState private var searchFocused: Bool

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let visible = cache.tasks(in: tasks, status: filter.status, query: query)
        VStack(spacing: 0) {
            accessory()
                .padding(.horizontal, Self.margin)
                .padding(.vertical, 12)
            if visible.isEmpty {
                emptyState
            } else {
                list(visible)
            }
        }
        // Title and search live in the window toolbar, like System Settings.
        .navigationTitle(filter.label)
        .navigationSubtitle(subtitle(count: visible.count))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                searchField.frame(width: 220)
            }
        }
        .onChange(of: searchRequest) { searchFocused = true }
    }

    private func subtitle(count: Int) -> String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(count) \(count == 1 ? "task" : "tasks") · \(date)"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // First Esc clears the text; a second one leaves the field.
                .onExitCommand {
                    if query.isEmpty { searchFocused = false } else { query = "" }
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
    }

    /// A `List` is backed by a recycling table, so only the rows on screen exist however many tasks
    /// there are.
    private func list(_ visible: [Task]) -> some View {
        List(visible) { task in
            TaskCard(
                task: task, appearance: appearance,
                setStatus: { status in
                    report(Outcome.run { try store.setStatus(id: task.id, to: status) })
                },
                edit: { edit(task) },
                delete: { report(Outcome.run { try store.delete(id: task.id) }) }
            )
            .listRowInsets(
                EdgeInsets(
                    top: appearance.compactCards ? 4 : 6, leading: Self.margin - Self.listRowSideInset,
                    bottom: appearance.compactCards ? 4 : 6, trailing: Self.margin - Self.listRowSideInset)
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
        } else if tasks.count(nil) == 0 {
            ContentUnavailableView(
                "No tasks yet", systemImage: "checklist",
                description: Text("Add your first one to get started."))
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
        var query: String
    }

    func tasks(in set: TaskSet, status: Status?, query: String) -> [Task] {
        let wanted = Key(revision: set.revision, status: status, query: query)
        if wanted != key {
            result = set.visible(status: status, query: query)
            key = wanted
        }
        return result
    }
}
