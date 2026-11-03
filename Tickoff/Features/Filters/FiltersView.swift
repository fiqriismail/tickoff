import SwiftUI

/// The sidebar: shell-supplied project rows above the status filters (counted within the chosen
/// project). Navigation only; nothing critical sits at the bottom edge, where a moved window can
/// hide it. It owns the `List`, so it also reconciles the project and filter choices into the one
/// selection the List reports.
struct FiltersView<Projects: View>: View {
    let tasks: TaskSet
    @Binding var scope: ProjectScope
    @Binding var filter: Filter
    @ViewBuilder let projects: () -> Projects

    var body: some View {
        List(selection: selection) {
            projects()
            Section("Library") {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Label(filter.label, systemImage: filter.symbol)
                        .badge(tasks.count(filter.status, project: scope.projectID))
                        .tag(AnyHashable(filter))
                }
            }
        }
    }

    private var selection: Binding<Set<AnyHashable>> {
        Binding(
            get: { SidebarSelection.selection(scope: scope, filter: filter) },
            set: {
                let next = SidebarSelection.reconcile($0, scope: scope, filter: filter)
                scope = next.scope
                filter = next.filter
            })
    }
}
