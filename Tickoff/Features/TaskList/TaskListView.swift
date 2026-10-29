import AppKit
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

    /// The content margin; header, add bar and cards all align to it.
    private static var margin: CGFloat { 16 }
    /// The side padding `List` adds around every row itself, subtracted so cards line up with the header.
    private static var listRowSideInset: CGFloat { 10 }

    @State private var query = ""
    @State private var cache = VisibleCache()
    @FocusState private var searchFocused: Bool
    /// The search field rests as a magnifier and expands on click or Find.
    @State private var searchOpen = false
    @State private var clickAway = ClickAwayMonitor()

    private var searchExpanded: Bool { searchOpen || searching }

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
                // Fills the rest so the add bar stays pinned under the toolbar.
                emptyState.frame(maxHeight: .infinity)
            } else {
                list(visible)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Title and search live in the window toolbar, like System Settings.
        .navigationTitle(filter.label)
        .navigationSubtitle(subtitle(count: visible.count))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { searchField }
                .removingSharedBackground()
        }
        .onAppear { clickAway.start {
                searchFocused = false
                if query.isEmpty { withAnimation(.smooth(duration: 0.25)) { searchOpen = false } }
            } }
        .onDisappear { clickAway.stop() }
        .onChange(of: searchRequest) { openSearch() }
        .onChange(of: searchFocused) { collapseSearch() }
    }

    private func subtitle(count: Int) -> String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(count) \(count == 1 ? "task" : "tasks") · \(date)"
    }

    private func openSearch() {
        withAnimation(.smooth(duration: 0.25)) { searchOpen = true }
        searchFocused = true
    }

    /// Folds back into the magnifier, but only when there is no search text to keep visible.
    private func collapseSearch() {
        guard !searchFocused, query.isEmpty else { return }
        withAnimation(.smooth(duration: 0.25)) { searchOpen = false }
    }

    /// The toolbar item has a fixed width and draws its own background, so growing and shrinking
    /// is a plain in-view animation rather than a toolbar relayout.
    private var searchField: some View {
        HStack(spacing: 6) {
            Button(action: openSearch) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .help("Search tasks")
            .accessibilityLabel("Search")
            if searchExpanded {
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
                    .padding(.trailing, 10)
                }
            }
        }
        .frame(width: searchExpanded ? 220 : 34, height: 34, alignment: .leading)
        .searchBackground()
        .frame(width: 220, alignment: .trailing)
        .animation(.smooth(duration: 0.25), value: searchExpanded)
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

extension View {
    /// The pill behind the search field: Liquid Glass where available, a quiet fill before.
    @ViewBuilder fileprivate func searchBackground() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.quaternary, in: Capsule())
        }
    }
}

extension ToolbarContent {
    /// Drops the system's shared pill behind a toolbar item so the item can draw its own.
    @ToolbarContentBuilder fileprivate func removingSharedBackground() -> some ToolbarContent {
        if #available(macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Reports mouse-downs outside the focused text field. macOS keeps a field focused when the user
/// clicks empty space, so the search field could otherwise never notice it had been left.
@MainActor
private final class ClickAwayMonitor {
    private var token: Any?

    func start(onOutsideClick: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                guard let window = event.window, let editor = window.firstResponder as? NSText,
                    let root = window.contentView?.superview
                else { return }
                let hit = root.hitTest(root.convert(event.locationInWindow, from: nil))
                if let hit, hit.isDescendant(of: editor) || editor.isDescendant(of: hit) { return }
                window.makeFirstResponder(nil)
                onOutsideClick()
            }
            return event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
