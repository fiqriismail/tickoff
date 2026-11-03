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
        try store.save(Appearance(compactCards: true, showNotes: false))

        #expect(SettingsModel(store: store).appearance.compactCards == true)
        #expect(SettingsModel(store: store).appearance.showNotes == false)
    }

    @Test func anEditAppliesImmediatelyAndPersists() throws {
        let (model, store, _) = try makeModel()
        model.update { $0.compactCards = true }

        #expect(model.appearance.compactCards == true)
        #expect(try store.load().compactCards == true)
        #expect(model.errorMessage == nil)
    }

    @Test func aFailedSaveKeepsTheEditOnScreenAndReportsTheError() throws {
        let (model, _, database) = try makeModel()
        model.update { $0.compactCards = true }
        try database.queue.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_all BEFORE UPDATE ON settings
                    BEGIN SELECT RAISE(ABORT, 'nope'); END
                    """)
        }

        model.update { $0.showNotes = false }

        #expect(model.appearance.showNotes == false)
        #expect(model.errorMessage?.contains("Couldn't save") == true)
    }

    @Test func aSuccessfulSaveClearsEarlierError() throws {
        let (model, _, database) = try makeModel()
        model.update { $0.compactCards = true }
        try database.queue.write { db in
            try db.execute(
                sql: "CREATE TRIGGER reject_all BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, 'nope'); END")
        }
        model.update { $0.showNotes = false }
        #expect(model.errorMessage != nil)

        try database.queue.write { db in try db.execute(sql: "DROP TRIGGER reject_all") }
        model.update { $0.compactCards = false }
        #expect(model.errorMessage == nil)
    }

    @Test func settingTheSameValueDoesNotWriteAgain() throws {
        let (model, _, database) = try makeModel()
        model.update { $0.showNotes = false }
        try database.queue.write { db in
            try db.execute(
                sql: "CREATE TRIGGER reject_all BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, 'nope'); END")
        }

        model.update { $0.showNotes = false }

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
