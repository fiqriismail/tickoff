import Testing

@testable import Tickoff

struct TaskTests {
    @Test func enumsRoundTripThroughTheDatabaseRepresentation() {
        for status in Status.allCases {
            #expect(Status(dbValue: status.dbValue) == status)
        }
        for priority in Priority.allCases {
            #expect(Priority(dbValue: priority.dbValue) == priority)
        }
    }

    @Test func enumsKeepTheIntegerCodesTheRustAppWrote() {
        #expect(Status.allCases.map(\.dbValue) == [0, 1, 2])
        #expect(Priority.allCases.map(\.dbValue) == [0, 1, 2])
    }

    @Test func unknownStoredValuesFallBackToTodoAndMedium() {
        #expect(Status(dbValue: 99) == .todo)
        #expect(Status(dbValue: -1) == .todo)
        #expect(Priority(dbValue: 99) == .medium)
        #expect(Priority(dbValue: -1) == .medium)
    }

    @Test func statusCyclesBackToTheStart() {
        #expect(Status.todo.next.next.next == .todo)
    }

    @Test func labelsAreTheUserFacingNames() {
        #expect(Status.allCases.map(\.label) == ["To do", "In progress", "Done"])
        #expect(Priority.allCases.map(\.label) == ["Low", "Medium", "High"])
    }
}
