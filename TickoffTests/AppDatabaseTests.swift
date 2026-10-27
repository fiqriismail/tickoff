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
        #expect(applied == ["v1"])
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
}
