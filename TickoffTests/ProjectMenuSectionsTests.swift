import Testing

@testable import Tickoff

struct ProjectMenuSectionsTests {
    private func project(_ id: Int64, _ name: String, inbox: Bool = false) -> Project {
        Project(id: id, name: name, colour: .system, notes: "", archived: false, isInbox: inbox)
    }

    private var projects: [Project] {
        [project(1, "Inbox", inbox: true), project(2, "Apple"), project(3, "Banana"), project(4, "Cherry")]
    }

    @Test func inboxIsSeparateAndAllListsTheRestInOrder() {
        let sections = ProjectMenuSections(projects: projects, recentIDs: [])

        #expect(sections.inbox?.name == "Inbox")
        #expect(sections.recent.isEmpty)
        #expect(sections.all.map(\.name) == ["Apple", "Banana", "Cherry"])
    }

    @Test func recentFollowsTheGivenOrderAndStillAppearsUnderAll() {
        let sections = ProjectMenuSections(projects: projects, recentIDs: [4, 2])

        #expect(sections.recent.map(\.name) == ["Cherry", "Apple"])
        #expect(sections.all.map(\.name) == ["Apple", "Banana", "Cherry"])
    }

    @Test func recentSkipsInboxAndProjectsThatAreNoLongerAvailable() {
        let sections = ProjectMenuSections(projects: projects, recentIDs: [1, 99, 3])

        #expect(sections.recent.map(\.name) == ["Banana"])
    }
}
