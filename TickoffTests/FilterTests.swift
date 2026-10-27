import Testing

@testable import Tickoff

struct FilterTests {
    @Test func statusMatchesItsOption() {
        #expect(Filter.all.status == nil)
        #expect(Filter.status(.done).status == .done)
    }

    @Test func theSidebarOffersAllThenEachStatusInOrder() {
        #expect(Filter.allCases == [.all, .status(.todo), .status(.inProgress), .status(.done)])
        #expect(
            Filter.allCases.map(\.label) == ["All tasks", "To do", "In progress", "Done"])
    }
}
