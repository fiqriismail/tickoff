import Foundation
import GRDB

/// The one place that talks SQL about the `tasks` table.
struct TaskStore: Sendable {
    let database: AppDatabase

    /// Open tasks first, then by priority, then by due date (undated last), newest first.
    func loadAll() throws -> [Task] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title, notes, priority, status, due FROM tasks
                    ORDER BY (status = 2), priority DESC, (due = ''), due, id DESC
                    """
            ).map(Self.task(from:))
        }
    }

    @discardableResult
    func insert(title: String, priority: Priority) throws -> Int64 {
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO tasks (title, priority) VALUES (?, ?)",
                arguments: [title, priority.dbValue])
            return db.lastInsertedRowID
        }
    }

    /// Returns how many rows changed: 0 if the task no longer exists.
    @discardableResult
    func update(_ task: Task) throws -> Int {
        try database.queue.write { db in
            try db.execute(
                sql: """
                    UPDATE tasks SET title = ?, notes = ?, priority = ?, status = ?, due = ?
                    WHERE id = ?
                    """,
                arguments: [
                    task.title, task.notes, task.priority.dbValue, task.status.dbValue, task.due,
                    task.id,
                ])
            return db.changesCount
        }
    }

    @discardableResult
    func setStatus(id: Int64, to status: Status) throws -> Int {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE tasks SET status = ? WHERE id = ?",
                arguments: [status.dbValue, id])
            return db.changesCount
        }
    }

    @discardableResult
    func delete(id: Int64) throws -> Int {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id])
            return db.changesCount
        }
    }

    @discardableResult
    func clearCompleted() throws -> Int {
        try database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM tasks WHERE status = ?", arguments: [Status.done.dbValue])
            return db.changesCount
        }
    }

    // Reads each column leniently (a bad value falls back instead of trapping), because the
    // file may have been written by an older build or edited by hand.
    private static func task(from row: Row) -> Task {
        Task(
            id: Int64.fromDatabaseValue(row[0]) ?? 0,
            title: String.fromDatabaseValue(row[1]) ?? "",
            notes: String.fromDatabaseValue(row[2]) ?? "",
            priority: Priority(dbValue: Int.fromDatabaseValue(row[3]) ?? Priority.medium.dbValue),
            status: Status(dbValue: Int.fromDatabaseValue(row[4]) ?? Status.todo.dbValue),
            due: String.fromDatabaseValue(row[5]) ?? "")
    }
}
