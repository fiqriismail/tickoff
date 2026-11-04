import Foundation
import GRDB
import Testing

@testable import Tickoff

/// Persistence and history behavior, always using throwaway databases and explicit calendar dates.
struct DailyGoalStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }

    private func fixture() throws -> (AppDatabase, DailyGoalStore, Int64) {
        let database = try AppDatabase()
        let projectID = try ProjectStore(database: database).create(name: "Health", kind: .dailyGoals)
        return (database, DailyGoalStore(database: database), projectID)
    }

    @Test func checkOffCanBeCompletedAndUndoneWithoutChangingTasks() throws {
        let (db, store, project) = try fixture()
        try TaskStore(database: db).insert(title: "ordinary", priority: .medium)
        let id = try store.create(
            projectID: project, name: "  Meditate  ", tracking: .checkOff, target: 1, date: date(4),
            calendar: calendar)
        try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        let complete = try #require(try store.loadToday(date: date(4), calendar: calendar).first)
        #expect(complete.name == "Meditate")
        #expect(complete.isComplete)
        try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        #expect(try store.loadToday(date: date(4), calendar: calendar).first?.value == 0)
        #expect(try TaskStore(database: db).loadAll().first?.status == .todo)
    }

    @Test func countersAllowOverachievementAndNeverGoBelowZero() throws {
        let (_, store, project) = try fixture()
        let id = try store.create(
            projectID: project, name: "Water", tracking: .counter, target: 2, date: date(4),
            calendar: calendar)
        try store.changeProgress(id: id, increment: false, date: date(4), calendar: calendar)
        #expect(try store.loadToday(date: date(4), calendar: calendar).first?.value == 0)
        for _ in 0..<3 {
            try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        }
        let day = try #require(try store.loadToday(date: date(4), calendar: calendar).first)
        #expect(day.value == 3 && day.target == 2 && day.isComplete)
    }

    @Test func blankNamesAndInvalidTargetsAreRejected() throws {
        let (_, store, project) = try fixture()
        #expect(throws: GoalError.blankName) {
            try store.create(projectID: project, name: " \n ", tracking: .checkOff, target: 1)
        }
        for target in [0, -1] {
            #expect(throws: GoalError.invalidTarget) {
                try store.create(projectID: project, name: "Water", tracking: .counter, target: target)
            }
        }
    }

    @Test func aNewDayStartsAtZeroAndKeepsYesterdayUnchanged() throws {
        let (db, store, project) = try fixture()
        let id = try store.create(
            projectID: project, name: "Walk", tracking: .checkOff, target: 1, date: date(4),
            calendar: calendar)
        try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        #expect(try store.loadToday(date: date(5), calendar: calendar).first?.value == 0)
        let previous = try db.queue.read {
            try Int.fetchOne($0, sql: "SELECT value FROM daily_goal_progress WHERE goal_id = ? AND day = ?",
                             arguments: [id, "2026-11-04"])
        }
        #expect(previous == 1)
    }

    @Test func templateEditsApplyTomorrowWithoutReinterpretingTodaysProgress() throws {
        let (_, store, project) = try fixture()
        let id = try store.create(
            projectID: project, name: "Water", tracking: .counter, target: 8, date: date(4),
            calendar: calendar)
        try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        let row = try #require(try store.loadToday(date: date(4), calendar: calendar).first)
        var changed = row.goal
        changed.name = "Drink water"
        changed.tracking = .checkOff
        changed.target = 1
        try store.update(changed, date: date(4), calendar: calendar)
        let today = try #require(try store.loadToday(date: date(4), calendar: calendar).first)
        #expect(today.name == "Water" && today.target == 8 && today.tracking == .counter)
        #expect(today.value == 1 && !today.isComplete && today.hasPendingChanges)
        // Even after the template becomes a check-off, today's + still increments a counter.
        try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        #expect(try store.loadToday(date: date(4), calendar: calendar).first?.value == 2)
        let tomorrow = try #require(try store.loadToday(date: date(5), calendar: calendar).first)
        #expect(tomorrow.name == "Drink water" && tomorrow.tracking == .checkOff)
        #expect(tomorrow.target == 1 && tomorrow.value == 0 && !tomorrow.hasPendingChanges)
    }

    @Test func anActionAfterMidnightUsesTheNewDayRatherThanTheDisplayedOldDay() throws {
        let (db, store, project) = try fixture()
        let id = try store.create(
            projectID: project, name: "Read", tracking: .counter, target: 3, date: date(4),
            calendar: calendar)
        try store.changeProgress(id: id, increment: true, date: date(5), calendar: calendar)
        let values = try db.queue.read {
            try Int.fetchAll($0, sql: "SELECT value FROM daily_goal_progress ORDER BY day")
        }
        #expect(values == [0, 1])
    }

    @Test func removingAGoalHidesItButKeepsItsHistoryAndRejectsFutureWrites() throws {
        let (db, store, project) = try fixture()
        let id = try store.create(projectID: project, name: "Read", tracking: .checkOff, target: 1)
        try store.changeProgress(id: id, increment: true)
        try store.remove(id: id)
        #expect(try store.loadToday(date: .now).isEmpty)
        #expect(throws: GoalError.unavailable) { try store.changeProgress(id: id, increment: true) }
        let count = try db.queue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM daily_goal_progress WHERE goal_id = ?",
                             arguments: [id])
        }
        #expect(count == 1)
    }

    @Test func archivingAProjectStopsSnapshotsAndWritesWithoutLosingHistory() throws {
        let (db, store, project) = try fixture()
        let id = try store.create(
            projectID: project, name: "Read", tracking: .checkOff, target: 1,
            date: date(4), calendar: calendar)
        let projects = ProjectStore(database: db)
        try projects.setArchived(id: project, true)
        #expect(try store.loadToday(date: date(5), calendar: calendar).isEmpty)
        #expect(throws: ProjectError.wrongKind) {
            try store.changeProgress(id: id, increment: true, date: date(5), calendar: calendar)
        }
        let count = try db.queue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM daily_goal_progress")
        }
        #expect(count == 1)
        try projects.setArchived(id: project, false)
        #expect(try store.loadToday(date: date(5), calendar: calendar).first?.value == 0)
    }

    @Test func deletingAProjectPreservesSnapshotsButRemovesItFromToday() throws {
        let (db, store, project) = try fixture()
        try store.create(projectID: project, name: "Read", tracking: .checkOff, target: 1)
        try ProjectStore(database: db).delete(id: project)
        #expect(try store.loadToday(date: .now).isEmpty)
        #expect(try db.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM daily_goal_progress") } == 1)
    }

    @Test func goalsAndTasksCannotBeWrittenToTheWrongProjectType() throws {
        let (db, store, project) = try fixture()
        #expect(throws: ProjectError.wrongKind) {
            try store.create(projectID: Project.inboxID, name: "Read", tracking: .checkOff, target: 1)
        }
        #expect(throws: ProjectError.wrongKind) {
            try TaskStore(database: db).insert(title: "Task", priority: .medium, projectID: project)
        }
        let id = try TaskStore(database: db).insert(title: "Task", priority: .medium)
        var task = try #require(try TaskStore(database: db).loadAll().first { $0.id == id })
        task.projectID = project
        #expect(throws: ProjectError.wrongKind) { try TaskStore(database: db).update(task) }
    }

    @Test func clearingTasksNeverDeletesHiddenLegacyRowsInGoalProjects() throws {
        let (db, _, project) = try fixture()
        try db.queue.write {
            try $0.execute(
                sql: "INSERT INTO tasks (title, status, project_id) VALUES (?, ?, ?), (?, ?, ?)",
                arguments: [
                    "Visible", Status.done.dbValue, Project.inboxID,
                    "Legacy", Status.done.dbValue, project,
                ])
        }
        let tasks = TaskStore(database: db)
        #expect(try tasks.loadAll().map(\.title) == ["Visible"])
        #expect(try tasks.clearCompleted() == 1)
        #expect(try tasks.clearCompleted(project: project) == 0)
        #expect(try db.queue.read {
            try String.fetchAll($0, sql: "SELECT title FROM tasks")
        } == ["Legacy"])
    }

    @Test func dailyProgressAndTemplatesSurviveReopeningAFile() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "goals-\(UUID()).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try AppDatabase(path: path)
            let project = try ProjectStore(database: db).create(name: "Health", kind: .dailyGoals)
            let store = DailyGoalStore(database: db)
            let id = try store.create(
                projectID: project, name: "Water", tracking: .counter, target: 8,
                date: date(4), calendar: calendar)
            try store.changeProgress(id: id, increment: true, date: date(4), calendar: calendar)
        }
        let reopened = DailyGoalStore(database: try AppDatabase(path: path))
        let row = try #require(try reopened.loadToday(date: date(4), calendar: calendar).first)
        #expect(row.value == 1 && row.target == 8)
    }

    @Test func countersReportOverflowRatherThanWrapping() throws {
        let (db, store, project) = try fixture()
        let id = try store.create(projectID: project, name: "Steps", tracking: .counter, target: 1)
        try db.queue.write {
            try $0.execute(sql: "UPDATE daily_goal_progress SET value = ? WHERE goal_id = ?",
                           arguments: [Int.max, id])
        }
        #expect(throws: GoalError.progressLimit) { try store.changeProgress(id: id, increment: true) }
    }
}
