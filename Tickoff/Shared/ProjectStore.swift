import Foundation
import GRDB

/// The one place that talks SQL about the `projects` table. Deleting a project also removes its
/// tasks through `TaskStore` and hides its goals through `DailyGoalStore`, preserving recorded history.
struct ProjectStore: Sendable {
    let database: AppDatabase

    /// Inbox first, then the rest alphabetically (case-insensitive).
    func loadAll() throws -> [Project] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, name, colour, notes, archived, is_inbox, kind FROM projects
                    ORDER BY is_inbox DESC, name COLLATE NOCASE
                    """
            ).map(Self.project(from:))
        }
    }

    @discardableResult
    func create(
        name: String, colour: ProjectColour = .system, notes: String = "", kind: ProjectKind = .tasks
    ) throws -> Int64 {
        let name = try Self.validated(name)
        return try database.queue.write { db in
            try Self.requireUnique(name, excluding: nil, in: db)
            try db.execute(
                sql: "INSERT INTO projects (name, colour, notes, kind) VALUES (?, ?, ?, ?)",
                arguments: [name, colour.key, notes, kind.rawValue])
            return db.lastInsertedRowID
        }
    }

    /// Saves the name, colour and notes (not the archived flag; see `setArchived`).
    func update(_ project: Project) throws {
        let name = try Self.validated(project.name)
        try database.queue.write { db in
            try Self.requireKind(project.kind, id: project.id, in: db)
            try Self.requireUnique(name, excluding: project.id, in: db)
            try db.execute(
                sql: "UPDATE projects SET name = ?, colour = ?, notes = ? WHERE id = ?",
                arguments: [name, project.colour.key, project.notes, project.id])
            if db.changesCount == 0 { throw ProjectError.notFound }
        }
    }

    func setArchived(id: Int64, _ archived: Bool) throws {
        try database.queue.write { db in
            try Self.requireNotInbox(id, in: db)
            try db.execute(
                sql: "UPDATE projects SET archived = ? WHERE id = ?",
                arguments: [archived ? 1 : 0, id])
            if db.changesCount == 0 { throw ProjectError.notFound }
        }
    }

    /// Deletes the project's tasks, hides its goals and removes the project in one transaction.
    func delete(id: Int64) throws {
        try database.queue.write { db in
            try Self.requireNotInbox(id, in: db)
            try TaskStore.deleteTasks(inProject: id, in: db)
            try DailyGoalStore.removeGoals(inProject: id, in: db)
            try db.execute(sql: "DELETE FROM projects WHERE id = ?", arguments: [id])
            if db.changesCount == 0 { throw ProjectError.notFound }
        }
    }

    /// Cross-table callers use this guard instead of querying projects themselves.
    static func requireKind(
        _ kind: ProjectKind, id: Int64, activeOnly: Bool = false, in db: Database
    ) throws {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT kind, archived FROM projects WHERE id = ?", arguments: [id])
        else { throw ProjectError.notFound }
        let stored = ProjectKind(rawValue: row["kind"]) ?? .tasks
        let archived: Bool = row["archived"]
        guard stored == kind, !activeOnly || !archived else {
            throw ProjectError.wrongKind
        }
    }

    static func dailyGoalProjectIDs(activeOnly: Bool = false, in db: Database) throws -> [Int64] {
        try Int64.fetchAll(
            db, sql: "SELECT id FROM projects WHERE kind = ? AND (? = 0 OR archived = 0)",
            arguments: [ProjectKind.dailyGoals.rawValue, activeOnly])
    }

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ProjectError.blankName }
        return trimmed
    }

    // Checked here as well as by the column's UNIQUE NOCASE so the user gets a readable message.
    private static func requireUnique(_ name: String, excluding id: Int64?, in db: Database) throws {
        let clash = try Int64.fetchOne(
            db,
            sql: "SELECT id FROM projects WHERE name = ? COLLATE NOCASE AND id IS NOT ?",
            arguments: [name, id])
        if clash != nil { throw ProjectError.duplicateName(name) }
    }

    private static func requireNotInbox(_ id: Int64, in db: Database) throws {
        let isInbox = try Int.fetchOne(
            db, sql: "SELECT is_inbox FROM projects WHERE id = ?", arguments: [id])
        if isInbox == 1 { throw ProjectError.inboxProtected }
    }

    // Lenient like `TaskStore.task(from:)`: a bad colour falls back to the system accent.
    private static func project(from row: Row) -> Project {
        Project(
            id: Int64.fromDatabaseValue(row[0]) ?? 0,
            name: String.fromDatabaseValue(row[1]) ?? "",
            colour: String.fromDatabaseValue(row[2]).flatMap(ProjectColour.init(key:)) ?? .system,
            notes: String.fromDatabaseValue(row[3]) ?? "",
            archived: Int.fromDatabaseValue(row[4]) == 1,
            isInbox: Int.fromDatabaseValue(row[5]) == 1,
            kind: String.fromDatabaseValue(row[6]).flatMap(ProjectKind.init(rawValue:)) ?? .tasks)
    }
}
