import Testing

@testable import Tickoff

/// Goal-editor input validation without UI interaction.
struct GoalDraftTests {
    @Test func draftsTrimNamesAndRequirePositiveWholeNumberCounterTargets() throws {
        var draft = GoalDraft()
        draft.name = "  Drink water  "
        draft.tracking = .counter
        for target in ["", "0", "-2", "1.5", "eight"] {
            draft.target = target
            #expect(throws: GoalError.invalidTarget) { try draft.validated(projectID: 2) }
        }
        draft.target = "8"
        let goal = try draft.validated(projectID: 2)
        #expect(goal.name == "Drink water" && goal.target == 8 && goal.projectID == 2)
        draft.name = " \n "
        #expect(throws: GoalError.blankName) { try draft.validated(projectID: 2) }
    }

    @Test func checkOffIgnoresCounterInputAndExistingDraftKeepsItsIdentity() throws {
        var draft = GoalDraft()
        draft.name = "Read"
        draft.target = "not a counter"
        #expect(try draft.validated(projectID: 2).target == 1)
        let original = DailyGoal(id: 5, projectID: 2, name: "Water", tracking: .counter, target: 8)
        let saved = try GoalDraft(goal: original).validated(projectID: 2)
        #expect(saved == original)
    }
}
