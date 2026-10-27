import GRDB
import Testing

@testable import Tickoff

@MainActor
struct SettingsModelTests {
    private func makeModel() throws -> (SettingsModel, SettingsStore, AppDatabase) {
        let database = try AppDatabase()
        let store = SettingsStore(database: database)
        return (SettingsModel(store: store), store, database)
    }

    @Test func aNewModelStartsWithTheSavedSettings() throws {
        let database = try AppDatabase()
        let store = SettingsStore(database: database)
        try store.save(Appearance(mode: .dark, accent: .rose))

        #expect(SettingsModel(store: store).appearance.mode == .dark)
        #expect(SettingsModel(store: store).appearance.accent == .rose)
    }

    @Test func anEditAppliesImmediatelyAndPersists() throws {
        let (model, store, _) = try makeModel()
        model.update { $0.accent = .violet }

        #expect(model.appearance.accent == .violet)
        #expect(try store.load().accent == .violet)
        #expect(model.errorMessage == nil)
    }

    @Test func resetRestoresTheDefaultsAndPersistsThem() throws {
        let (model, store, _) = try makeModel()
        model.update {
            $0.mode = .light
            $0.compactCards = true
        }
        model.resetToDefaults()

        #expect(model.appearance == .default)
        #expect(try store.load() == .default)
    }

    @Test func aFailedSaveKeepsTheEditOnScreenAndReportsTheError() throws {
        let (model, _, database) = try makeModel()
        model.update { $0.scale = .small }
        try database.queue.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_all BEFORE UPDATE ON settings
                    BEGIN SELECT RAISE(ABORT, 'nope'); END
                    """)
        }

        model.update { $0.scale = .large }

        #expect(model.appearance.scale == .large)
        #expect(model.errorMessage?.contains("Couldn't save") == true)
    }

    @Test func aSuccessfulSaveClearsEarlierError() throws {
        let (model, _, database) = try makeModel()
        model.update { $0.scale = .small }
        try database.queue.write { db in
            try db.execute(
                sql: "CREATE TRIGGER reject_all BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, 'nope'); END")
        }
        model.update { $0.scale = .large }
        #expect(model.errorMessage != nil)

        try database.queue.write { db in try db.execute(sql: "DROP TRIGGER reject_all") }
        model.update { $0.scale = .standard }
        #expect(model.errorMessage == nil)
    }

    @Test func settingTheSameValueDoesNotWriteAgain() throws {
        let (model, _, database) = try makeModel()
        model.update { $0.mode = .dark }
        try database.queue.write { db in
            try db.execute(
                sql: "CREATE TRIGGER reject_all BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, 'nope'); END")
        }

        model.update { $0.mode = .dark }

        #expect(model.errorMessage == nil)
    }

    @Test func aFailedLoadFallsBackToDefaultsAndReportsIt() throws {
        let database = try AppDatabase()
        try database.queue.write { db in try db.execute(sql: "DROP TABLE settings") }

        let model = SettingsModel(store: SettingsStore(database: database))

        #expect(model.appearance == .default)
        #expect(model.errorMessage?.contains("Couldn't load") == true)
    }
}
