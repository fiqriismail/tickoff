import Testing

@testable import Tickoff

struct TaskSetTests {
    private func make(_ title: String, _ status: Status, notes: String = "Milk") -> Task {
        Task(id: 1, title: title, notes: notes, priority: .medium, status: status, due: "")
    }

    @Test func countsAndSearchesWithoutRescanning() {
        var set = TaskSet()
        set.replace([make("Buy Eggs", .todo), make("Call", .done)])

        #expect(set.count(nil) == 2)
        #expect(set.count(.done) == 1)
        #expect(set.count(.inProgress) == 0)
        #expect(set.matches(index: 0, query: "eggs"))
        #expect(set.matches(index: 0, query: "milk"))
        #expect(set.matches(index: 0, query: ""))
        #expect(!set.matches(index: 1, query: "eggs"))
    }

    @Test func replacingBumpsTheRevisionAndResetsTheCounts() {
        var set = TaskSet()
        set.replace([make("a", .todo)])
        let before = set.revision

        set.replace([])

        #expect(set.revision > before)
        #expect(set.count(nil) == 0)
        #expect(set.count(.todo) == 0)
    }

    @Test func visibleFiltersByStatusAndIgnoresCaseAndPadding() {
        var set = TaskSet()
        set.replace([make("Buy Eggs", .todo), make("Eggs benedict", .done), make("Call", .todo)])

        #expect(set.visible(status: nil, query: "").count == 3)
        #expect(set.visible(status: .todo, query: "  EGGS ").map(\.title) == ["Buy Eggs"])
        #expect(set.visible(status: .done, query: "milk").map(\.title) == ["Eggs benedict"])
        #expect(set.visible(status: .inProgress, query: "").isEmpty)
    }
}
