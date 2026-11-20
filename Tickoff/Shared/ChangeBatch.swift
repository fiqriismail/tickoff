import Foundation
import GRDB

/// One change the assistant proposes and the user approved. Pure data: `ChangeBatch` applies it.
enum ProposedChange: Equatable, Sendable {
    case addTask(title: String, priority: Priority, projectID: Int64)
    /// Only the non-nil fields change.
    case editTask(id: Int64, title: String? = nil, notes: String? = nil, priority: Priority? = nil, due: String? = nil)
    case setStatus(taskID: Int64, Status)
    case moveTask(id: Int64, toProject: Int64)
    case deleteTask(id: Int64)
    case changeGoalProgress(goalID: Int64, increment: Bool)
}

/// Why a proposed change could not be applied; the message is shown to the user as-is.
enum ChangeError: LocalizedError, Equatable {
    case taskNotFound(Int64)
    case blankTitle
    /// The project is missing, archived or a daily-goal project, so it cannot hold tasks.
    case projectUnavailable(Int64)

    var errorDescription: String? {
        switch self {
        case .taskNotFound: "A task in the proposal no longer exists."
        case .blankTitle: "A task needs a title."
        case .projectUnavailable: "A project in the proposal is archived, removed or doesn’t hold tasks."
        }
    }
}

/// Applies approved `ProposedChange`s atomically. It holds no SQL: every change goes through an
/// `in db:` helper on the store that owns the table, inside a single transaction.
struct ChangeBatch: Sendable {
    let database: AppDatabase

    /// All-or-nothing: the first invalid change throws, which rolls the whole batch back.
    func apply(_ changes: [ProposedChange], date: Date = .now, calendar: Calendar = .current) -> Outcome {
        Outcome.run {
            try database.queue.write { db in
                for change in changes {
                    try Self.apply(change, date: date, calendar: calendar, in: db)
                }
            }
        }
    }

    private static func apply(
        _ change: ProposedChange, date: Date, calendar: Calendar, in db: Database
    ) throws {
        switch change {
        case .addTask(let title, let priority, let projectID):
            try requireTaskProject(projectID, in: db)
            try TaskStore.insert(title: try validated(title), priority: priority, projectID: projectID, in: db)
        case .editTask(let id, let title, let notes, let priority, let due):
            var task = try requireTask(id, in: db)
            if let title { task.title = try validated(title) }
            if let notes { task.notes = notes }
            if let priority { task.priority = priority }
            if let due { task.due = due }
            try TaskStore.update(task, in: db)
        case .setStatus(let id, let status):
            try requireTask(id, in: db)
            try TaskStore.setStatus(id: id, to: status, in: db)
        case .moveTask(let id, let projectID):
            try requireTask(id, in: db)
            try requireTaskProject(projectID, in: db)
            try TaskStore.move(id: id, toProject: projectID, in: db)
        case .deleteTask(let id):
            try requireTask(id, in: db)
            try TaskStore.delete(id: id, in: db)
        case .changeGoalProgress(let goalID, let increment):
            try DailyGoalStore.changeProgress(
                id: goalID, increment: increment, date: date, calendar: calendar, in: db)
        }
    }

    @discardableResult
    private static func requireTask(_ id: Int64, in db: Database) throws -> Task {
        guard let task = try TaskStore.task(id: id, in: db) else { throw ChangeError.taskNotFound(id) }
        return task
    }

    /// Stricter than the store's own check: an archived project is also refused.
    private static func requireTaskProject(_ id: Int64, in db: Database) throws {
        do {
            try ProjectStore.requireKind(.tasks, id: id, activeOnly: true, in: db)
        } catch ProjectError.notFound, ProjectError.wrongKind {
            throw ChangeError.projectUnavailable(id)
        }
    }

    private static func validated(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ChangeError.blankTitle }
        return trimmed
    }
}
