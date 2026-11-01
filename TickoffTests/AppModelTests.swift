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

    @Test func perProjectCountsRefreshAfterATaskMovesProject() throws {
        let model = try seededModel()
        let work = try ProjectStore(database: model.database).create(name: "Work")
        #expect(model.tasks.count(nil, project: Project.inboxID) == 5)

        try model.database.queue.write { db in
            try db.execute(
                sql: "UPDATE tasks SET project_id = ? WHERE status = 2", arguments: [work])
        }
        model.reload()

        #expect(model.tasks.count(nil, project: Project.inboxID) == 3)
        #expect(model.tasks.count(.done, project: work) == 2)
    }

    @Test func startsScopedToAllProjectsAndListsVisibleProjects() throws {
        let model = try seededModel()
        let store = model.projectStore
        let old = try store.create(name: "Old")
        try store.setArchived(id: old, true)
        try store.create(name: "Work")
        model.reload()

        #expect(model.scope == .all)
        #expect(model.visibleProjects.map(\.name) == ["Inbox", "Work"])
    }

    @Test func selectingAProjectUpdatesTheScope() throws {
        let model = try seededModel()
        let work = try model.projectStore.create(name: "Work")
        model.reload()

        model.select(.project(work))
        #expect(model.scope == .project(work))
    }

    @Test func selectingAnUnknownOrArchivedProjectIsIgnored() throws {
        let model = try seededModel()
        let old = try model.projectStore.create(name: "Old")
        try model.projectStore.setArchived(id: old, true)
        model.reload()

        model.select(.project(old))
        model.select(.project(999))
        #expect(model.scope == .all)
    }

    @Test func theScopeFallsBackToAllProjectsWhenItsProjectIsDeleted() throws {
        let model = try seededModel()
        let work = try model.projectStore.create(name: "Work")
        model.reload()
        model.select(.project(work))

        try model.projectStore.delete(id: work)
        model.reload()

        #expect(model.scope == .all)
    }

    @Test func theScopeFallsBackToAllProjectsWhenItsProjectIsArchived() throws {
        let model = try seededModel()
        let work = try model.projectStore.create(name: "Work")
        model.reload()
        model.select(.project(work))

        try model.projectStore.setArchived(id: work, true)
        model.reload()

        #expect(model.scope == .all)
    }

    @Test func newTasksGoToTheSelectedProjectOrInboxUnderAllProjects() throws {
        let model = try seededModel()
        let work = try model.projectStore.create(name: "Work")
        model.reload()

        #expect(model.newTaskProjectID == Project.inboxID)
        model.select(.project(work))
        #expect(model.newTaskProjectID == work)
    }

    @Test func theEditPickerOffersVisibleProjectsPlusTheTasksOwnArchivedOne() throws {
        let model = try seededModel()
        let old = try model.projectStore.create(name: "Old")
        let other = try model.projectStore.create(name: "Other")
        try model.projectStore.setArchived(id: old, true)
        try model.projectStore.setArchived(id: other, true)
        try model.taskStore.insert(title: "stuck", priority: .low, projectID: old)
        model.reload()
        let task = try #require(model.tasks.items.first { $0.title == "stuck" })

        #expect(model.projectChoices(for: task).map(\.name) == ["Inbox", "Old"])
    }

    @Test func movingATaskInTheEditSheetMovesItInTheList() throws {
        let model = try seededModel()
        let work = try model.projectStore.create(name: "Work")
        model.reload()
        var task = try #require(model.tasks.items.first)

        task.projectID = work
        try model.taskStore.update(task)
        model.reload()

        #expect(model.tasks.visible(status: nil, project: work, query: "").map(\.id) == [task.id])
        #expect(model.tasks.count(nil, project: Project.inboxID) == 4)
    }

    @Test func projectUsedMovesItToTheFrontWithoutDuplicatesAndKeepsFive() throws {
        let model = try seededModel()
        for id in [1, 2, 3, 4, 5, 6] as [Int64] { model.projectUsed(id) }
        model.projectUsed(4)

        #expect(model.recentProjectIDs == [4, 6, 5, 3, 2])
    }

    @Test func recentProjectsAreSavedAndReloadedByANewModel() throws {
        let model = try seededModel()
        model.projectUsed(1)
        model.projectUsed(7)

        let reopened = AppModel(database: model.database)
        #expect(reopened.recentProjectIDs == [7, 1])
    }
}
