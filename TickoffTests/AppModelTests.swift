import GRDB
import Testing

@testable import Tickoff

@MainActor
struct AppModelTests {
    private func seededModel() throws -> AppModel {
        let database = try AppDatabase()
        try database.queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tasks (title, priority, status) VALUES
                        ('a', 1, 0), ('b', 1, 0), ('c', 1, 1), ('d', 1, 2), ('e', 1, 2)
                    """)
        }
        return AppModel(database: database)
    }

    private func breakTasksTable(_ model: AppModel) throws {
        try model.database.queue.write { db in try db.execute(sql: "DROP TABLE tasks") }
    }

    @Test func startsWithTheSeededTasksAndCorrectCounts() throws {
        let model = try seededModel()

        #expect(model.tasks.count(nil) == 5)
        #expect(model.tasks.count(.todo) == 2)
        #expect(model.tasks.count(.inProgress) == 1)
        #expect(model.tasks.count(.done) == 2)
        #expect(model.errorMessage == nil)
    }

    @Test func clearingCompletedRemovesOnlyDoneTasksAndReloads() throws {
        let model = try seededModel()

        model.handle(Outcome.run { try model.taskStore.clearCompleted() })

        #expect(model.tasks.count(nil) == 3)
        #expect(model.tasks.count(.done) == 0)
        #expect(model.tasks.count(.todo) == 2)
    }

    @Test func aChangedOutcomeClearsTheBanner() throws {
        let model = try seededModel()
        model.report(.failed("boom"))
        #expect(model.errorMessage == "boom")

        model.handle(.changed)

        #expect(model.errorMessage == nil)
    }

    @Test func aFailedOutcomeShowsTheMessage() throws {
        let model = try seededModel()

        model.handle(.failed("disk full"))

        #expect(model.errorMessage == "disk full")
        #expect(model.tasks.count(nil) == 5)
    }

    @Test func aDatabaseErrorShowsTheBannerAndKeepsTheLoadedTasks() throws {
        let model = try seededModel()
        try breakTasksTable(model)

        model.reload()

        #expect(model.errorMessage?.isEmpty == false)
        #expect(model.tasks.count(nil) == 5)
    }

    @Test func aFailingCommandIsReportedNotThrown() throws {
        let model = try seededModel()
        try breakTasksTable(model)

        model.handle(Outcome.run { try model.taskStore.clearCompleted() })

        #expect(model.errorMessage?.contains("tasks") == true)
    }

    @Test func dismissingClearsTheBanner() throws {
        let model = try seededModel()
        model.report(.failed("boom"))

        model.dismissError()

        #expect(model.errorMessage == nil)
    }

    @Test func aStartupErrorIsShownUntilTheNextSuccessfulCommand() throws {
        let model = AppModel(database: try AppDatabase(), startupError: "Couldn't open it")
        #expect(model.errorMessage == "Couldn't open it")

        model.handle(.changed)

        #expect(model.errorMessage == nil)
    }
}
