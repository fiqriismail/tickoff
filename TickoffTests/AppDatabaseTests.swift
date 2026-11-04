import Foundation
import GRDB
import Testing

@testable import Tickoff

struct AppDatabaseTests {
    /// The schema exactly as the Rust app's `shared/db.rs::migrate` created it, with no GRDB tables.
    private static let rustEraSchema = """
        CREATE TABLE tasks (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            title      TEXT    NOT NULL,
            notes      TEXT    NOT NULL DEFAULT '',
            priority   INTEGER NOT NULL DEFAULT 1,
            status     INTEGER NOT NULL DEFAULT 0,
            due        TEXT    NOT NULL DEFAULT '',
            created_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        INSERT INTO tasks (title, notes, priority, status, due) VALUES
            ('Write report', 'quarterly', 2, 1, '2026-11-02'),
            ('Buy milk', '', 0, 0, ''),
            ('Book flights', 'window seat', 1, 2, '2026-10-30');
        INSERT INTO settings (key, value) VALUES ('theme_mode', 'dark'), ('accent', 'teal');
        """

    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "tickoff-\(UUID().uuidString).db").path
    }

    private func writeRustEraFile(at path: String) throws {
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in try db.execute(sql: Self.rustEraSchema) }
    }

    @Test func aFileWrittenByTheRustAppLoadsUnchanged() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try writeRustEraFile(at: path)

        let store = TaskStore(database: try AppDatabase(path: path))
        let tasks = try store.loadAll()

        #expect(
            tasks.map(\.title) == ["Write report", "Buy milk", "Book flights"])
        let report = try #require(tasks.first)
        #expect(report.notes == "quarterly")
        #expect(report.priority == .high)
        #expect(report.status == .inProgress)
        #expect(report.due == "2026-11-02")
        #expect(tasks.last?.status == .done)
    }

    @Test func openingARustEraFileLeavesItsRowsAndSettingsUntouched() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try writeRustEraFile(at: path)

        let database = try AppDatabase(path: path)
        let (settings, taskCount) = try database.queue.read { db in
            (
                try Row.fetchAll(db, sql: "SELECT key, value FROM settings ORDER BY key")
                    .map { [$0[0] as String, $0[1] as String] },
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks")
            )
        }

        #expect(settings == [["accent", "teal"], ["theme_mode", "dark"]])
        #expect(taskCount == 3)
    }

    @Test func reopeningTheSameFileRunsTheMigrationOnlyOnce() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        _ = try AppDatabase(path: path)
        let reopened = try AppDatabase(path: path)

        let applied = try reopened.queue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        #expect(applied == ["v1", "v2", "v3"])
    }

    @Test func aNewDatabaseHasTheTasksAndSettingsTables() throws {
        let database = try AppDatabase()

        let tables = try database.queue.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name IN ('tasks', 'settings') ORDER BY name
                    """)
        }
        #expect(tables == ["settings", "tasks"])
    }

    @Test func tasksAddedByTheSwiftAppStayReadableAfterReopening() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try TaskStore(database: AppDatabase(path: path)).insert(title: "persisted", priority: .high)
        let reloaded = try TaskStore(database: AppDatabase(path: path)).loadAll()

        #expect(reloaded.map(\.title) == ["persisted"])
    }

    @Test func migratingARustEraFileMovesItsTasksIntoInbox() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try writeRustEraFile(at: path)

        let database = try AppDatabase(path: path)
        let (inbox, projectIDs) = try database.queue.read { db in
            (
                try Row.fetchOne(db, sql: "SELECT id, name, is_inbox FROM projects"),
                try Int64.fetchAll(db, sql: "SELECT DISTINCT project_id FROM tasks")
            )
        }

        let inboxRow = try #require(inbox)
        #expect(inboxRow["name"] == "Inbox")
        #expect(inboxRow["is_inbox"] == 1)
        #expect(projectIDs == [inboxRow["id"]])
    }

    @Test func migratingASecondTimeChangesNothing() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try writeRustEraFile(at: path)

        func snapshot(_ database: AppDatabase) throws -> [String] {
            try database.queue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT 'p:' || id || name || is_inbox FROM projects
                        UNION ALL SELECT 't:' || id || project_id FROM tasks
                        """
                ).map { $0[0] as String }
            }
        }
        let first = try snapshot(AppDatabase(path: path))
        let second = try snapshot(AppDatabase(path: path))

        #expect(first == second)
        #expect(first.count == 4)
    }

    @Test func tasksInsertedWithoutAProjectLandInInbox() throws {
        let database = try AppDatabase()
        try TaskStore(database: database).insert(title: "loose", priority: .low)

        let projectID = try database.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT project_id FROM tasks")
        }
        #expect(projectID == 1)
    }

    @Test func projectNamesAreUniqueIgnoringCase() throws {
        let database = try AppDatabase()

        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "INSERT INTO projects (name) VALUES ('inbox')")
            }
        }
    }

    @Test func aFreshFileAndTheInMemoryDatabaseShareOneSchema() throws {
        let path = temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        func schema(_ database: AppDatabase) throws -> [String] {
            try database.queue.read { db in
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT sql FROM sqlite_master
                        WHERE type = 'table' AND name IN ('tasks', 'settings', 'projects')
                        ORDER BY name
                        """)
            }
        }

        #expect(try schema(AppDatabase(path: path)) == schema(AppDatabase()))
    }
}
