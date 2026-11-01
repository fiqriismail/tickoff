import Foundation

/// The edit sheet's working copy of a task. Validation lives here so it can be tested without a view.
struct TaskDraft: Equatable {
    var id: Int64
    var title: String
    var notes: String
    var priority: Priority
    var status: Status
    var hasDue: Bool
    var dueDate: Date
    /// Carried through untouched until the edit sheet lets the user move a task (#7).
    var projectID: Int64

    struct ValidationError: Error, Equatable {
        var message: String
    }

    init(task: Task, today: Date = .now, calendar: Calendar = .current) {
        id = task.id
        projectID = task.projectID
        title = task.title
        notes = task.notes
        priority = task.priority
        status = task.status
        // A stored value that isn't a real date is dropped rather than shown as a bogus one.
        let date = task.dueDate(calendar: calendar)
        hasDue = date != nil
        dueDate = date ?? today
    }

    /// Trims the title, rejects a blank one, and stores the date as zero-padded `YYYY-MM-DD`
    /// (the list sorts `due` as text, so no other form may be stored).
    func validated(calendar: Calendar = .current) throws -> Task {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError(message: "A task needs a title.") }
        return Task(
            id: id, title: trimmed, notes: notes, priority: priority, status: status,
            due: hasDue ? Self.isoString(dueDate, calendar: calendar) : "",
            projectID: projectID)
    }

    static func isoString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
