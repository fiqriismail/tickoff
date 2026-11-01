import Testing

@testable import Tickoff

struct SidebarSelectionTests {
    private func reconcile(
        _ new: Set<AnyHashable>, scope: ProjectScope = .all, filter: Filter = .all
    ) -> (scope: ProjectScope, filter: Filter) {
        SidebarSelection.reconcile(new, scope: scope, filter: filter)
    }

    @Test func theSelectionHoldsTheCurrentScopeAndFilter() {
        let set = SidebarSelection.selection(scope: .project(2), filter: .status(.done))

        #expect(set == [AnyHashable(ProjectScope.project(2)), AnyHashable(Filter.status(.done))])
    }

    @Test func clickingAProjectChangesOnlyTheScope() {
        let new = SidebarSelection.selection(scope: .all, filter: .status(.todo))
            .union([AnyHashable(ProjectScope.project(3))])

        let result = reconcile(new, scope: .all, filter: .status(.todo))
        #expect(result.scope == .project(3))
        #expect(result.filter == .status(.todo))
    }

    @Test func clickingAFilterChangesOnlyTheFilter() {
        let new = SidebarSelection.selection(scope: .project(3), filter: .all)
            .union([AnyHashable(Filter.status(.done))])

        let result = reconcile(new, scope: .project(3), filter: .all)
        #expect(result.scope == .project(3))
        #expect(result.filter == .status(.done))
    }

    @Test func deselectingKeepsTheCurrentChoices() {
        let result = reconcile([], scope: .project(3), filter: .status(.done))

        #expect(result.scope == .project(3))
        #expect(result.filter == .status(.done))
    }
}
