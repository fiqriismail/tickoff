import Foundation
import GRDB
import Testing

@testable import Tickoff

struct ChangeBatchTests {
    private struct Fixture {
        let database: AppDatabase
        let tasks: TaskStore
        let projects: ProjectStore
        let goals: DailyGoalStore
        let batch: ChangeBatch

        init() throws {
            database = try AppDatabase()
            tasks = TaskStore(database: database)
            projects = ProjectStore(database: database)
            goals = DailyGoalStore(database: database)
            batch = ChangeBatch(database: database)
        }
    }

    @Test func addingATaskTrimsTheTitleAndFilesItInTheProject() throws {
        let f = try Fixture()
        let work = try f.projects.create(name: "Work")
        #expect(f.batch.apply([.addTask(title: "  Ship  ", priority: .high, projectID: work)]) == .changed)
        let task = try #require(try f.tasks.loadAll().first)
        #expect(task.title == "Ship" && task.priority == .high && task.projectID == work)
    }

    @Test func editingATaskChangesOnlyTheGivenFields() throws {
        let f = try Fixture()
        let id = try f.tasks.insert(title: "old", priority: .low)
        #expect(f.batch.apply([.editTask(id: id, title: "new", due: "2026-12-01")]) == .changed)
        let task = try #require(try f.tasks.loadAll().first)
        #expect(task.title == "new" && task.due == "2026-12-01" && task.priority == .low)
    }

    @Test func statusMoveAndDeleteApplyToExistingTasks() throws {
        let f = try Fixture()
        let work = try f.projects.create(name: "Work")
        let a = try f.tasks.insert(title: "a", priority: .medium)
        let b = try f.tasks.insert(title: "b", priority: .medium)
        let outcome = f.batch.apply([.setStatus(taskID: a, .done), .moveTask(id: a, toProject: work), .deleteTask(id: b)])
        #expect(outcome == .changed)
        let tasks = try f.tasks.loadAll()
        #expect(tasks.map(\.id) == [a])
        #expect(tasks.first?.status == .done && tasks.first?.projectID == work)
    }

    @Test func goalProgressChangesInTheSameBatchAsTasks() throws {
        let f = try Fixture()
        let project = try f.projects.create(name: "Health", kind: .dailyGoals)
        let goal = try f.goals.create(projectID: project, name: "Water", tracking: .counter, target: 3)
        let outcome = f.batch.apply([
            .addTask(title: "t", priority: .low, projectID: Project.inboxID),
            .changeGoalProgress(goalID: goal, increment: true),
            .changeGoalProgress(goalID: goal, increment: true),
        ])
        #expect(outcome == .changed)
        #expect(try f.goals.loadToday(date: .now).first?.value == 2)
        #expect(try f.tasks.loadAll().count == 1)
    }

    @Test func aBatchWithOneInvalidChangeLeavesTheDatabaseUnchanged() throws {
        let f = try Fixture()
        let id = try f.tasks.insert(title: "keep", priority: .medium)
        let outcome = f.batch.apply([
            .addTask(title: "new", priority: .low, projectID: Project.inboxID),
            .setStatus(taskID: id, .done),
            .deleteTask(id: 9_999),
        ])
        #expect(outcome == .failed(ChangeError.taskNotFound(9_999).localizedDescription))
        let tasks = try f.tasks.loadAll()
        #expect(tasks.map(\.title) == ["keep"] && tasks.first?.status == .todo)
    }

    @Test func tasksCannotGoToArchivedOrDailyGoalProjects() throws {
        let f = try Fixture()
        let archived = try f.projects.create(name: "Old")
        try f.projects.setArchived(id: archived, true)
        let goals = try f.projects.create(name: "Habits", kind: .dailyGoals)
        let id = try f.tasks.insert(title: "t", priority: .medium)
        for project in [archived, goals, 9_999] {
            let message = ChangeError.projectUnavailable(project).localizedDescription
            #expect(f.batch.apply([.addTask(title: "x", priority: .low, projectID: project)]) == .failed(message))
            #expect(f.batch.apply([.moveTask(id: id, toProject: project)]) == .failed(message))
        }
        #expect(try f.tasks.loadAll().map(\.projectID) == [Project.inboxID])
    }

    @Test func blankTitlesAndUnknownGoalsAreRejectedWithReadableMessages() throws {
        let f = try Fixture()
        #expect(f.batch.apply([.addTask(title: " ", priority: .low, projectID: Project.inboxID)])
            == .failed(ChangeError.blankTitle.localizedDescription))
        #expect(f.batch.apply([.changeGoalProgress(goalID: 42, increment: true)])
            == .failed(GoalError.unavailable.localizedDescription))
    }

    @Test func taskHelpersReportZeroRowsForMissingTasks() throws {
        let f = try Fixture()
        let counts = try f.database.queue.write { db in
            [
                try TaskStore.setStatus(id: 7, to: .done, in: db),
                try TaskStore.move(id: 7, toProject: Project.inboxID, in: db),
                try TaskStore.delete(id: 7, in: db),
            ]
        }
        let missing = try f.database.queue.read { db in try TaskStore.task(id: 7, in: db) }
        #expect(counts == [0, 0, 0] && missing == nil)
    }
}
