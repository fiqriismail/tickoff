import Testing

@testable import Tickoff

struct ProjectDraftTests {
    private let work = Project(
        id: 7, name: "Work", colour: .teal, notes: "n", archived: true, isInbox: false)

    @Test func aNewDraftIsBlankWithTheSystemColour() {
        let draft = ProjectDraft()

        #expect(draft.id == nil && draft.name.isEmpty && draft.colour == .system)
        #expect(!draft.archived && !draft.isInbox)
    }

    @Test func validationTrimsTheName() throws {
        var draft = ProjectDraft()
        draft.name = "  Home \n"

        #expect(try draft.validated().name == "Home")
    }

    @Test func aBlankNameIsRefused() {
        var draft = ProjectDraft()
        draft.name = "   "

        #expect(throws: ProjectError.blankName) { try draft.validated() }
    }

    @Test func editingKeepsEveryFieldOfTheProject() throws {
        #expect(try ProjectDraft(project: work).validated() == work)
    }
}
