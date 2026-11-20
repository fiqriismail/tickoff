import Foundation
import GRDB

/// The one place that talks SQL about the `tasks` table.
struct TaskStore: Sendable {
    let database: AppDatabase

    /// Open tasks first, then by priority, then by due date (undated last), newest first.
    func loadAll() throws -> [Task] {
        try database.queue.read { db in
            let dailyIDs = Set(try ProjectStore.dailyGoalProjectIDs(in: db))
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title, notes, priority, status, due, project_id FROM tasks
                    ORDER BY (status = 2), priority DESC, (due = ''), due, id DESC
                    """
            ).map(Self.task(from:)).filter { !dailyIDs.contains($0.projectID) }
        }
    }

    @discardableResult
    func insert(title: String, priority: Priority, projectID: Int64 = Project.inboxID) throws -> Int64 {
        try database.queue.write { db in
            try Self.insert(title: title, priority: priority, projectID: projectID, in: db)
        }
    }

    /// Returns how many rows changed: 0 if the task no longer exists.
    @discardableResult
    func update(_ task: Task) throws -> Int {
        try database.queue.write { db in try Self.update(task, in: db) }
    }

    @discardableResult
    func setStatus(id: Int64, to status: Status) throws -> Int {
        try database.queue.write { db in try Self.setStatus(id: id, to: status, in: db) }
    }

    @discardableResult
    func delete(id: Int64) throws -> Int {
        try database.queue.write { db in try Self.delete(id: id, in: db) }
    }

    /// Deletes completed tasks in task projects only; hidden legacy rows in goal projects stay untouched.
    @discardableResult
    func clearCompleted(project: Int64? = nil) throws -> Int {
        try database.queue.write { db in
            let dailyIDs = Set(try ProjectStore.dailyGoalProjectIDs(in: db))
            let projects = try project.map { [$0] } ?? Int64.fetchAll(
                db, sql: "SELECT DISTINCT project_id FROM tasks WHERE status = ?",
                arguments: [Status.done.dbValue])
            var deleted = 0
            for id in projects where !dailyIDs.contains(id) {
                try db.execute(
                    sql: "DELETE FROM tasks WHERE status = ? AND project_id = ?",
                    arguments: [Status.done.dbValue, id])
                deleted += db.changesCount
            }
            return deleted
        }
    }

    // The `in db:` helpers below run inside the caller's transaction, so a batch of changes
    // (`ChangeBatch`) commits or rolls back as one. The instance methods above wrap them.

    @discardableResult
    static func insert(
        title: String, priority: Priority, projectID: Int64 = Project.inboxID, in db: Database
    ) throws -> Int64 {
        try ProjectStore.requireKind(.tasks, id: projectID, in: db)
        try db.execute(
            sql: "INSERT INTO tasks (title, priority, project_id) VALUES (?, ?, ?)",
            arguments: [title, priority.dbValue, projectID])
        return db.lastInsertedRowID
    }

    /// Returns how many rows changed: 0 if the task no longer exists.
    @discardableResult
    static func update(_ task: Task, in db: Database) throws -> Int {
        try ProjectStore.requireKind(.tasks, id: task.projectID, in: db)
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

    @discardableResult
    static func setStatus(id: Int64, to status: Status, in db: Database) throws -> Int {
        try db.execute(sql: "UPDATE tasks SET status = ? WHERE id = ?", arguments: [status.dbValue, id])
        return db.changesCount
    }

    /// Moves a task into a task project; 0 rows changed if the task no longer exists.
    @discardableResult
    static func move(id: Int64, toProject projectID: Int64, in db: Database) throws -> Int {
        try ProjectStore.requireKind(.tasks, id: projectID, in: db)
        try db.execute(
            sql: "UPDATE tasks SET project_id = ? WHERE id = ?", arguments: [projectID, id])
        return db.changesCount
    }

    @discardableResult
    static func delete(id: Int64, in db: Database) throws -> Int {
        try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id])
        return db.changesCount
    }

    /// The task with this id, or nil. Unlike `loadAll` it does not hide goal-project rows.
    static func task(id: Int64, in db: Database) throws -> Task? {
        try Row.fetchOne(
            db, sql: "SELECT id, title, notes, priority, status, due, project_id FROM tasks WHERE id = ?",
            arguments: [id]
        ).map(Self.task(from:))
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
