import GRDB
import Testing

@testable import Tickoff

struct SettingsStoreTests {
    private let custom = Appearance(
        mode: .light, accent: .teal, scale: .large, compactCards: true, showNotes: false)

    private func makeStore() throws -> (SettingsStore, AppDatabase) {
        let database = try AppDatabase()
        return (SettingsStore(database: database), database)
    }

    @Test func aFreshDatabaseLoadsTheDefaults() throws {
        let (store, _) = try makeStore()
        #expect(try store.load() == .default)
    }

    @Test func theDefaultsAreSystemSystemDefaultCompactOffNotesOn() {
        let defaults = Appearance.default
        #expect(defaults.mode == .system)
        #expect(defaults.accent == .system)
        #expect(defaults.scale == .standard)
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
                    CREATE TRIGGER reject_scale BEFORE UPDATE ON settings
                    WHEN NEW.key = 'ui_scale' BEGIN SELECT RAISE(ABORT, 'nope'); END
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
                        ('theme_mode', 'neon'), ('mystery', 'x'), ('accent', 'rose'),
                        ('ui_scale', 'huge')
                    """)
        }

        let loaded = try store.load()
        #expect(loaded.mode == Appearance.default.mode)
        #expect(loaded.accent == .rose)
        #expect(loaded.scale == Appearance.default.scale)
    }

    @Test func settingsWrittenByTheRustAppLoadUnchanged() throws {
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
                    mode: .dark, accent: .orange, scale: .small, compactCards: true,
                    showNotes: false))
    }

    @Test func savingWritesTheKeysAndValuesTheRustAppReads() throws {
        let (store, database) = try makeStore()
        try store.save(custom)

        let stored = try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value FROM settings ORDER BY key")
                .map { "\($0[0] as String)=\($0[1] as String)" }
        }
        #expect(
            stored == [
                "accent=teal", "compact_cards=true", "show_notes=false", "theme_mode=light",
                "ui_scale=large",
            ])
    }

    @Test func savingTwiceKeepsOneRowPerKey() throws {
        let (store, database) = try makeStore()
        try store.save(custom)
        try store.save(.default)

        let count = try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings")
        }
        #expect(count == 5)
    }
}
