import Foundation

/// The loaded tasks plus everything derived from them, computed once per load instead of once
/// per view update. The shell owns the one `TaskSet` and passes it down by value or reference.
struct TaskSet: Sendable {
    private(set) var items: [Task] = []
    /// Lower-cased title and notes of each task, for case-insensitive search.
    private var searchKeys: [String] = []
    private var counts = [Int](repeating: 0, count: Status.allCases.count)
    /// The same per-status counts for each project id, so the sidebar can scope without scanning.
    private var projectCounts: [Int64: [Int]] = [:]
    /// Changes every time the contents are replaced; caches key on it.
    private(set) var revision = 0

    /// Swaps in freshly loaded tasks and bumps `revision`.
    mutating func replace(_ newItems: [Task]) {
        searchKeys = newItems.map { "\($0.title)\n\($0.notes)".lowercased() }
        counts = [Int](repeating: 0, count: Status.allCases.count)
        projectCounts = [:]
        for task in newItems {
            counts[task.status.dbValue] += 1
            projectCounts[task.projectID, default: [Int](repeating: 0, count: counts.count)][
                task.status.dbValue] += 1
        }
        items = newItems
        revision += 1
    }

    /// Number of tasks with `status` (all statuses when `nil`), within `project` (all projects
    /// when `nil`).
    func count(_ status: Status?, project: Int64? = nil) -> Int {
        guard let project else {
            guard let status else { return items.count }
            return counts[status.dbValue]
        }
        guard let perStatus = projectCounts[project] else { return 0 }
        guard let status else { return perStatus.reduce(0, +) }
        return perStatus[status.dbValue]
    }

    /// Whether task `index` contains `query`, which must already be lower-case.
    func matches(index: Int, query: String) -> Bool {
        query.isEmpty || searchKeys[index].contains(query)
    }

    /// Tasks with `status` (all when `nil`) whose title or notes contain `query`, ignoring case
    /// and surrounding whitespace, in load order.
    func visible(status: Status?, query: String) -> [Task] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.indices.compactMap { index in
            let task = items[index]
            guard status == nil || task.status == status else { return nil }
            return matches(index: index, query: needle) ? task : nil
        }
    }
}
