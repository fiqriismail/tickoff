import Foundation

/// Where a task is in its life. The raw values are the integers already stored in `tasks.status`.
enum Status: Int, CaseIterable, Sendable {
    case todo = 0
    case inProgress = 1
    case done = 2

    var label: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }

    /// The status a pill click moves to, wrapping from done back to to do.
    var next: Status {
        switch self {
        case .todo: .inProgress
        case .inProgress: .done
        case .done: .todo
        }
    }

    var dbValue: Int { rawValue }

    /// Unknown stored values fall back to `.todo`, so a hand-edited file still loads.
    init(dbValue: Int) {
        self = Status(rawValue: dbValue) ?? .todo
    }
}

/// The raw values are the integers already stored in `tasks.priority`.
enum Priority: Int, CaseIterable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var dbValue: Int { rawValue }

    /// Unknown stored values fall back to `.medium`.
    init(dbValue: Int) {
        self = Priority(rawValue: dbValue) ?? .medium
    }
}

// Shadows Swift's concurrency `Task` inside this module (the issue and the data contract name it
// `Task`); spell it `_Concurrency.Task` where the concurrency type is needed.
struct Task: Identifiable, Equatable, Sendable {
    var id: Int64
    var title: String
    var notes: String
    var priority: Priority
    var status: Status
    /// ISO date (`YYYY-MM-DD`), empty when there is no due date.
    var due: String

    var isDone: Bool { status == .done }

    /// The due date at the start of its day, or `nil` when there is none or it isn't a real
    /// `YYYY-MM-DD` date (a hand-edited file may hold anything).
    func dueDate(calendar: Calendar = .current) -> Date? {
        let parts = due.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
            let day = Int(parts[2])
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        // `date(from:)` rolls impossible dates over (Feb 31 becomes Mar 3); reject those.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
