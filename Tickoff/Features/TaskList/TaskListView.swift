import SwiftUI

/// The detail column: a header with the filter name and count, a search field (⌘F), and a lazily
/// built list of task cards. It holds no task data of its own; the shell's `TaskSet` is passed in.
struct TaskListView: View {
    let tasks: TaskSet
    let filter: Filter
    let appearance: Appearance
    let store: TaskStore
    let report: (Outcome) -> Void
    /// Opens the edit dialog; the shell decides what that means.
    let edit: (Task) -> Void

    @State private var query = ""
    @State private var cache = VisibleCache()
    @FocusState private var searchFocused: Bool

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let visible = cache.tasks(in: tasks, status: filter.status, query: query)
        VStack(spacing: 0) {
            header(count: visible.count)
            if visible.isEmpty {
                emptyState
            } else {
                list(visible)
            }
        }
        .background {
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(filter.label).font(appearance.font(1.8, weight: .bold))
                    Text("\(count)")
                        .font(appearance.font(1.1, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(appearance.font(0.9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            searchField.frame(maxWidth: 260)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
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
                    top: appearance.compactCards ? 4 : 7, leading: 24,
                    bottom: appearance.compactCards ? 4 : 7, trailing: 24)
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
