import GRDB
import Testing

@testable import Tickoff

struct TaskStoreTests {
    private func makeStore() throws -> (TaskStore, AppDatabase) {
        let database = try AppDatabase()
        return (TaskStore(database: database), database)
    }

    @Test func loadAllOrdersOpenHighPriorityDatedTasksFirst() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tasks (title, priority, status, due) VALUES
                        ('done high',   2, 2, ''),
                        ('low',         0, 0, ''),
                        ('high undated',2, 0, ''),
                        ('high dated',  2, 0, '2026-12-01')
                    """)
        }

        let titles = try store.loadAll().map(\.title)
        #expect(titles == ["high dated", "high undated", "low", "done high"])
    }

    @Test func loadAllPutsNewestFirstWhenEverythingElseTies() throws {
        let (store, _) = try makeStore()
        try store.insert(title: "first", priority: .medium)
        try store.insert(title: "second", priority: .medium)

        #expect(try store.loadAll().map(\.title) == ["second", "first"])
    }

    @Test func insertCreatesATodoTaskWithTheGivenPriority() throws {
        let (store, _) = try makeStore()
        let id = try store.insert(title: "Write tests", priority: .high)

        let task = try #require(store.loadAll().first)
        #expect(task.id == id)
        #expect(task.title == "Write tests")
        #expect(task.priority == .high)
        #expect(task.status == .todo)
        #expect(task.notes == "")
        #expect(task.due == "")
    }

    @Test func titlesWithQuotesAreStoredLiterally() throws {
        let (store, _) = try makeStore()
        let title = "Robert'); DROP TABLE tasks;--"
        try store.insert(title: title, priority: .low)

        #expect(try store.loadAll().map(\.title) == [title])
    }

    @Test func updatePersistsEveryField() throws {
        let (store, _) = try makeStore()
        let id = try store.insert(title: "old", priority: .low)

        let edited = Task(
            id: id, title: "new", notes: "details", priority: .high, status: .inProgress,
            due: "2026-12-01", projectID: Project.inboxID)
        #expect(try store.update(edited) == 1)

        #expect(try store.loadAll() == [edited])
    }

    @Test func updateOfAMissingTaskChangesNothing() throws {
        let (store, _) = try makeStore()
        let ghost = Task(
            id: 42, title: "ghost", notes: "", priority: .medium, status: .todo, due: "",
            projectID: Project.inboxID)

        #expect(try store.update(ghost) == 0)
        #expect(try store.loadAll().isEmpty)
    }

    @Test func setStatusAndDeleteAffectOnlyTheGivenTask() throws {
        let (store, _) = try makeStore()
        let a = try store.insert(title: "a", priority: .medium)
        let b = try store.insert(title: "b", priority: .medium)

        try store.setStatus(id: a, to: .done)
        try store.delete(id: b)

        let tasks = try store.loadAll()
        #expect(tasks.count == 1)
        #expect(tasks.first?.id == a)
        #expect(tasks.first?.status == .done)
    }

    @Test func clearCompletedOnlyRemovesDoneTasks() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO tasks (title, status) VALUES ('a', 0), ('b', 1), ('c', 2), ('d', 2)")
        }

        #expect(try store.clearCompleted() == 2)
        #expect(try store.loadAll().map(\.title).sorted() == ["a", "b"])
    }

    @Test func unknownStatusAndPriorityCodesLoadAsTodoAndMedium() throws {
        let (store, database) = try makeStore()
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO tasks (title, priority, status) VALUES ('odd', 9, 7)")
        }

        let task = try #require(store.loadAll().first)
        #expect(task.status == .todo)
        #expect(task.priority == .medium)
    }

    @Test func insertWithoutAProjectUsesInbox() throws {
        let (store, _) = try makeStore()
        try store.insert(title: "loose", priority: .medium)

        #expect(try store.loadAll().map(\.projectID) == [Project.inboxID])
    }

    @Test func insertStoresTheGivenProject() throws {
        let (store, database) = try makeStore()
        let work = try ProjectStore(database: database).create(name: "Work")
        try store.insert(title: "report", priority: .medium, projectID: work)

        #expect(try store.loadAll().map(\.projectID) == [work])
    }

    @Test func updateMovesATaskToAnotherProject() throws {
        let (store, database) = try makeStore()
        let work = try ProjectStore(database: database).create(name: "Work")
        let id = try store.insert(title: "report", priority: .medium)
        var task = try #require(try store.loadAll().first { $0.id == id })

        task.projectID = work
        try store.update(task)

        #expect(try store.loadAll().first?.projectID == work)
    }

    @Test func clearCompletedCanBeLimitedToOneProject() throws {
        let (store, database) = try makeStore()
        let work = try ProjectStore(database: database).create(name: "Work")
        let inboxDone = try store.insert(title: "inbox done", priority: .low)
        let workDone = try store.insert(title: "work done", priority: .low, projectID: work)
        try store.insert(title: "work open", priority: .low, projectID: work)
        try store.setStatus(id: inboxDone, to: .done)
        try store.setStatus(id: workDone, to: .done)

        #expect(try store.clearCompleted(project: work) == 1)
        #expect(Set(try store.loadAll().map(\.title)) == ["inbox done", "work open"])
    }
}
