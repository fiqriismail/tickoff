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
                    SELECT id, title, notes, priority, status, due, project_id FROM tasks
                    ORDER BY (status = 2), priority DESC, (due = ''), due, id DESC
                    """
            ).map(Self.task(from:))
        }
    }

    @discardableResult
    func insert(title: String, priority: Priority, projectID: Int64 = Project.inboxID) throws -> Int64 {
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO tasks (title, priority, project_id) VALUES (?, ?, ?)",
                arguments: [title, priority.dbValue, projectID])
            return db.lastInsertedRowID
        }
    }

    /// Returns how many rows changed: 0 if the task no longer exists.
    @discardableResult
    func update(_ task: Task) throws -> Int {
        try database.queue.write { db in
            try db.execute(
                sql: """
                    UPDATE tasks SET title = ?, notes = ?, priority = ?, status = ?, due = ?,
                        project_id = ?
                    WHERE id = ?
                    """,
                arguments: [
                    task.title, task.notes, task.priority.dbValue, task.status.dbValue, task.due,
                    task.projectID, task.id,
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

    /// Deletes the done tasks of `project`, or of every project when it is `nil`.
    @discardableResult
    func clearCompleted(project: Int64? = nil) throws -> Int {
        try database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM tasks WHERE status = ? AND (? IS NULL OR project_id = ?)",
                arguments: [Status.done.dbValue, project, project])
            return db.changesCount
        }
    }

    /// Runs inside the caller's transaction so `ProjectStore.delete` removes tasks and project together.
    static func deleteTasks(inProject projectID: Int64, in db: Database) throws {
        try db.execute(sql: "DELETE FROM tasks WHERE project_id = ?", arguments: [projectID])
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
            due: String.fromDatabaseValue(row[5]) ?? "",
            projectID: Int64.fromDatabaseValue(row[6]) ?? Project.inboxID)
    }
}
