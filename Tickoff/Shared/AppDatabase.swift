import Foundation
import GRDB

/// Opens the SQLite file and owns its schema. It runs migrations and hands out the queue;
/// each table's queries live in exactly one store (`TaskStore`, later `SettingsStore`).
struct AppDatabase: Sendable {
    let queue: DatabaseQueue

    /// Opens (creating if needed) the database at `path` and brings its schema up to date.
    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(queue)
    }

    /// A throwaway database for tests.
    init() throws {
        queue = try DatabaseQueue()
        try Self.migrator.migrate(queue)
    }

    /// `~/.hello_gui/tasks.db`, the file the Rust-era app used; the folder is created on first run.
    static func openDefault() throws -> AppDatabase {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".hello_gui", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try AppDatabase(path: directory.appending(path: "tasks.db").path)
    }

    // `v1` is the schema the Rust app created, with IF NOT EXISTS so a Rust-era file adopts it
    // untouched. Later migrations must stay additive so an older build can still open the file.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(
                sql: """
                    CREATE TABLE IF NOT EXISTS tasks (
                        id         INTEGER PRIMARY KEY AUTOINCREMENT,
                        title      TEXT    NOT NULL,
                        notes      TEXT    NOT NULL DEFAULT '',
                        priority   INTEGER NOT NULL DEFAULT 1,
                        status     INTEGER NOT NULL DEFAULT 0,
                        due        TEXT    NOT NULL DEFAULT '',
                        created_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    CREATE TABLE IF NOT EXISTS settings (
                        key   TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                    """)
        }
        // `v2` adds projects. Inbox is seeded with id 1 so it can be `tasks.project_id`'s default:
        // existing rows are backfilled by the column default, and an older build that inserts
        // tasks without knowing about projects still lands them in Inbox.
        migrator.registerMigration("v2") { db in
            try db.execute(
                sql: """
                    CREATE TABLE projects (
                        id       INTEGER PRIMARY KEY AUTOINCREMENT,
                        name     TEXT    NOT NULL UNIQUE COLLATE NOCASE,
                        colour   TEXT    NOT NULL DEFAULT 'system',
                        notes    TEXT    NOT NULL DEFAULT '',
                        archived INTEGER NOT NULL DEFAULT 0,
                        is_inbox INTEGER NOT NULL DEFAULT 0
                    );
                    INSERT INTO projects (id, name, is_inbox) VALUES (1, 'Inbox', 1);
                    ALTER TABLE tasks ADD COLUMN project_id INTEGER NOT NULL DEFAULT 1;
                    """)
        }
        migrator.registerMigration("v3") { db in
            try db.execute(
                sql: """
                    ALTER TABLE projects ADD COLUMN kind TEXT NOT NULL DEFAULT 'tasks';
                    CREATE TABLE daily_goals (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        project_id INTEGER NOT NULL,
                        name TEXT NOT NULL,
                        tracking TEXT NOT NULL,
                        target INTEGER NOT NULL CHECK (target > 0),
                        removed INTEGER NOT NULL DEFAULT 0
                    );
                    CREATE INDEX daily_goals_project ON daily_goals (project_id, removed);
                    CREATE TABLE daily_goal_progress (
                        goal_id INTEGER NOT NULL,
                        day TEXT NOT NULL,
                        name TEXT NOT NULL,
                        tracking TEXT NOT NULL,
                        target INTEGER NOT NULL CHECK (target > 0),
                        value INTEGER NOT NULL DEFAULT 0 CHECK (value >= 0),
                        PRIMARY KEY (goal_id, day)
                    );
                    """)
        }
        return migrator
    }
}
