import Testing

@testable import Tickoff

struct ProgressSummaryTests {
    @Test func reportsDoneOutOfTotal() {
        #expect(ProgressSummary.text(done: 2, total: 10) == "2 of 10 completed")
    }

    @Test func saysNoTasksWhenThereAreNone() {
        #expect(ProgressSummary.text(done: 0, total: 0) == "No tasks")
    }
}
