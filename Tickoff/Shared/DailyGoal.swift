import Foundation

/// A persistent goal definition; daily progress keeps its own snapshot so edits cannot rewrite history.
struct DailyGoal: Identifiable, Equatable, Sendable {
    let id: Int64
    let projectID: Int64
    var name: String
    var tracking: GoalTracking
    var target: Int
}

/// Today's frozen definition and progress, shared by the Today feature and sidebar summaries.
struct GoalDay: Identifiable, Equatable, Sendable {
    let goal: DailyGoal
    let day: String
    let name: String
    let tracking: GoalTracking
    let target: Int
    let value: Int

    var id: Int64 { goal.id }
    var isComplete: Bool { value >= target }
    var hasPendingChanges: Bool {
        name != goal.name || tracking != goal.tracking || target != goal.target
    }
}

/// Stable persistence keys for the two daily tracking styles.
enum GoalTracking: String, CaseIterable, Sendable {
    case checkOff = "check_off"
    case counter

    var label: String {
        switch self {
        case .checkOff: "Daily Check-off"
        case .counter: "Counter"
        }
    }
}

/// Local calendar dates, not elapsed 24-hour intervals, define daily goal boundaries.
enum GoalDate {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Validation failures surfaced by the editor or the shell's error banner.
enum GoalError: LocalizedError, Equatable {
    case blankName
    case invalidTarget
    case unavailable
    case progressLimit

    var errorDescription: String? {
        switch self {
        case .blankName: "A goal needs a name."
        case .invalidTarget: "Enter a positive whole-number target."
        case .unavailable: "That goal is no longer available."
        case .progressLimit: "The counter has reached its supported limit."
        }
    }
}
