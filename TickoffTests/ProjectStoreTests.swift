import GRDB
import Testing

@testable import Tickoff

struct ProjectStoreTests {
    @Test func projectTypesRoundTripAndCannotBeConverted() throws {
        let database = try AppDatabase()
        let store = ProjectStore(database: database)
        let id = try store.create(name: "Health", kind: .dailyGoals)
        var goalProject = try #require(try store.loadAll().first { $0.id == id })
        #expect(goalProject.kind == .dailyGoals)
        #expect(try store.loadAll().first { $0.isInbox }?.kind == .tasks)
        goalProject.kind = .tasks
        #expect(throws: ProjectError.wrongKind) { try store.update(goalProject) }
        #expect(try store.loadAll().first { $0.id == id }?.kind == .dailyGoals)
    }

    private func makeStore() throws -> (ProjectStore, AppDatabase) {
        let database = try AppDatabase()
        return (ProjectStore(database: database), database)
    }

    private func insertTask(_ title: String, project: Int64, in database: AppDatabase) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO tasks (title, project_id) VALUES (?, ?)",
                arguments: [title, project])
        }
    }

    private func taskTitles(_ database: AppDatabase) throws -> [String] {
        try database.queue.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM tasks ORDER BY title")
        }
    }

    @Test func aNewDatabaseListsOnlyInbox() throws {
        let (store, _) = try makeStore()

        let projects = try store.loadAll()
        #expect(projects.map(\.name) == ["Inbox"])
        #expect(projects.first?.isInbox == true)
    }

    @Test func loadAllPutsInboxFirstThenSortsNamesIgnoringCase() throws {
        let (store, _) = try makeStore()
        try store.create(name: "zebra")
        try store.create(name: "Apple")
        try store.create(name: "banana")

        #expect(try store.loadAll().map(\.name) == ["Inbox", "Apple", "banana", "zebra"])
    }

    @Test func aProjectSavedWithEachColourReadsBackUnchanged() throws {
        let (store, _) = try makeStore()
        for colour in ProjectColour.allCases {
            let id = try store.create(name: "P-\(colour.key)", colour: colour)
            #expect(try store.loadAll().first { $0.id == id }?.colour == colour)
        }
    }

    @Test func createTrimsTheNameAndStoresColourAndNotes() throws {
        let (store, _) = try makeStore()
        let id = try store.create(name: "  Work  ", colour: .teal, notes: "day job")

        let project = try #require(try store.loadAll().first { $0.id == id })
        #expect(project.name == "Work")
        #expect(project.colour == .teal)
        #expect(project.notes == "day job")
        #expect(!project.archived && !project.isInbox)
    }

    @Test func blankNamesAreRejected() throws {
        let (store, _) = try makeStore()

        #expect(throws: ProjectError.blankName) { try store.create(name: "  \n ") }
    }

    @Test func duplicateNamesAreRejectedIgnoringCaseAndSpaces() throws {
        let (store, _) = try makeStore()
        try store.create(name: "Work")

        #expect(throws: ProjectError.duplicateName("work")) { try store.create(name: " work ") }
        #expect(throws: ProjectError.duplicateName("INBOX")) { try store.create(name: "INBOX") }
    }

    @Test func updateChangesNameColourAndNotesAndMayKeepItsOwnName() throws {
        let (store, _) = try makeStore()
        let id = try store.create(name: "Work")
        var project = try #require(try store.loadAll().first { $0.id == id })

        project.name = "WORK"  // same name, different case: not a clash with itself
        project.colour = .rose
        project.notes = "updated"
        try store.update(project)

        let saved = try #require(try store.loadAll().first { $0.id == id })
        #expect(saved.name == "WORK" && saved.colour == .rose && saved.notes == "updated")
    }

    @Test func updateRejectsANameAnotherProjectUses() throws {
        let (store, _) = try makeStore()
        try store.create(name: "Home")
        let id = try store.create(name: "Work")
        var project = try #require(try store.loadAll().first { $0.id == id })

        project.name = "home"
        #expect(throws: ProjectError.duplicateName("home")) { try store.update(project) }
    }

    @Test func updatingAMissingProjectReportsNotFound() throws {
        let (store, _) = try makeStore()
        let ghost = Project(
            id: 999, name: "Ghost", colour: .system, notes: "", archived: false, isInbox: false)

        #expect(throws: ProjectError.notFound) { try store.update(ghost) }
    }

    @Test func archivingAndUnarchivingTogglesTheFlag() throws {
        let (store, _) = try makeStore()
        let id = try store.create(name: "Old")

        try store.setArchived(id: id, true)
        #expect(try store.loadAll().first { $0.id == id }?.archived == true)
        try store.setArchived(id: id, false)
        #expect(try store.loadAll().first { $0.id == id }?.archived == false)
    }

    @Test func inboxCannotBeArchivedOrDeleted() throws {
        let (store, database) = try makeStore()
        try insertTask("keep me", project: 1, in: database)

        #expect(throws: ProjectError.inboxProtected) { try store.setArchived(id: 1, true) }
        #expect(throws: ProjectError.inboxProtected) { try store.delete(id: 1) }
        #expect(try store.loadAll().first?.archived == false)
        #expect(try taskTitles(database) == ["keep me"])
    }

    @Test func deleteRemovesOnlyThatProjectsTasks() throws {
        let (store, database) = try makeStore()
        let work = try store.create(name: "Work")
        let home = try store.create(name: "Home")
        try insertTask("inbox task", project: 1, in: database)
        try insertTask("work task", project: work, in: database)
        try insertTask("home task", project: home, in: database)

        try store.delete(id: work)

        #expect(try taskTitles(database) == ["home task", "inbox task"])
        #expect(try store.loadAll().map(\.name) == ["Inbox", "Home"])
    }

    @Test func deletingAMissingProjectReportsNotFound() throws {
        let (store, _) = try makeStore()

        #expect(throws: ProjectError.notFound) { try store.delete(id: 999) }
    }

    @Test func anUnrecognisedStoredColourFallsBackToSystem() throws {
        let (store, database) = try makeStore()
        let id = try store.create(name: "Odd")
        try database.queue.write { db in
            try db.execute(sql: "UPDATE projects SET colour = 'chartreuse' WHERE id = ?", arguments: [id])
        }

        #expect(try store.loadAll().first { $0.id == id }?.colour == .system)
    }
}
