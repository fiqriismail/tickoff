/// The sidebar is one `List` holding two independent choices (a project scope and a status
/// filter), so its selection is a set with one of each. This turns a set the List reports back
/// into the two choices.
enum SidebarSelection {
    /// The List's selection for the two current choices.
    static func selection(scope: ProjectScope, filter: Filter) -> Set<AnyHashable> {
        [AnyHashable(scope), AnyHashable(filter)]
    }

    /// A click adds one row to the set: it replaces the choice of its own kind. Anything else
    /// (a deselect, an empty set) keeps the current choices, so one is always selected.
    static func reconcile(
        _ new: Set<AnyHashable>, scope: ProjectScope, filter: Filter
    ) -> (scope: ProjectScope, filter: Filter) {
        let added = new.subtracting(selection(scope: scope, filter: filter))
        return (
            scope: added.compactMap { $0 as? ProjectScope }.first ?? scope,
            filter: added.compactMap { $0 as? Filter }.first ?? filter
        )
    }
}
