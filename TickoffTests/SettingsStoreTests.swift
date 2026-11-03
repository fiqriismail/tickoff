import GRDB
import Testing

@testable import Tickoff

struct SettingsStoreTests {
    private let custom = Appearance(compactCards: true, showNotes: false)

    private func makeStore() throws -> (SettingsStore, AppDatabase) {
        let database = try AppDatabase()
        return (SettingsStore(database: database), database)
    }

    @Test func aFreshDatabaseLoadsTheDefaults() throws {
        let (store, _) = try makeStore()
        #expect(try store.load() == .default)
    }

    @Test func theDefaultsAreCompactOffNotesOn() {
        let defaults = Appearance.default
        #expect(defaults.compactCards == false)
        #expect(defaults.showNotes == true)
    }

    @Test func savedSettingsAreLoadedBackAndCanBeOverwritten() throws {
        let (store, _) = try makeStore()
        try store.save(custom)
        #expect(try store.load() == custom)

        try store.save(.default)
        #expect(try store.load() == .default)
    }

    @Test func aFailedSaveLeavesTheOldSettingsUntouched() throws {
        let (store, database) = try makeStore()
        try store.save(.default)
        try database.queue.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_compact BEFORE UPDATE ON settings
                    WHEN NEW.key = 'compact_cards' BEGIN SELECT RAISE(ABORT, 'nope'); END
                    """)
        }

        #expect(throws: (any Error).self) { try store.save(custom) }
        #expect(try store.load() == .default)
    }

    @Test func unknownValuesAndKeysAreIgnored() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings VALUES
                        ('theme_mode', 'neon'), ('mystery', 'x'), ('compact_cards', 'maybe'),
                        ('ui_scale', 'huge')
                    """)
        }

        let loaded = try store.load()
        #expect(loaded.compactCards == false)
        #expect(loaded.showNotes == Appearance.default.showNotes)
    }

    @Test func settingsWrittenByOlderBuildsLoadAndTheRetiredKeysAreIgnored() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value) VALUES
                        ('theme_mode', 'dark'), ('accent', 'orange'), ('ui_scale', 'small'),
                        ('compact_cards', 'true'), ('show_notes', 'false')
                    """)
        }

        #expect(
            try store.load()
                == Appearance(
                    compactCards: true, showNotes: false))
    }

    @Test func savingWritesTheKeysAndValuesOlderBuildsRead() throws {
        let (store, database) = try makeStore()
        try store.save(custom)

        let stored = try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value FROM settings ORDER BY key")
                .map { "\($0[0] as String)=\($0[1] as String)" }
        }
        #expect(stored == ["compact_cards=true", "show_notes=false"])
    }

    @Test func savingTwiceKeepsOneRowPerKey() throws {
        let (store, database) = try makeStore()
        try store.save(custom)
        try store.save(.default)

        let count = try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings")
        }
        #expect(count == 2)
    }

    @Test func recentProjectsRoundTripInOrderAndStartEmpty() throws {
        let (store, _) = try makeStore()
        #expect(try store.loadRecentProjects().isEmpty)

        try store.saveRecentProjects([5, 2, 9])
        #expect(try store.loadRecentProjects() == [5, 2, 9])
        try store.saveRecentProjects([])
        #expect(try store.loadRecentProjects().isEmpty)
    }

    @Test func unreadableRecentProjectValuesAreSkipped() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO settings (key, value) VALUES ('recent_projects', '3,abc,,7')")
        }

        #expect(try store.loadRecentProjects() == [3, 7])
    }

    @Test func aLegacyTextSizeRowIsLeftUntouchedBySaving() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO settings VALUES ('ui_scale', 'large')")
        }

        try store.save(custom)

        let kept = try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'ui_scale'")
        }
        #expect(kept == "large")
    }
}

extension SettingsStoreTests {
    @Test func retiredThemeAndAccentRowsAreLeftUntouchedBySaving() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO settings VALUES ('theme_mode', 'dark'), ('accent', 'orange')")
        }

        try store.save(custom)

        let kept = try database.queue.read { db in
            try Row.fetchAll(
                db, sql: "SELECT key, value FROM settings WHERE key IN ('theme_mode','accent') ORDER BY key"
            ).map { "\($0[0] as String)=\($0[1] as String)" }
        }
        #expect(kept == ["accent=orange", "theme_mode=dark"])
    }
}
