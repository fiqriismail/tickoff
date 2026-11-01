/// How the add bar's project menu is laid out, so the ordering is testable without a view.
/// Inbox is always first; Recent holds the last-used projects; All lists every other project in
/// the order given (alphabetical, from the store), so a project is findable even if it's recent.
struct ProjectMenuSections: Equatable {
    var inbox: Project?
    var recent: [Project]
    var all: [Project]

    init(projects: [Project], recentIDs: [Int64]) {
        inbox = projects.first { $0.isInbox }
        let others = projects.filter { !$0.isInbox }
        let byID = Dictionary(uniqueKeysWithValues: others.map { ($0.id, $0) })
        recent = recentIDs.compactMap { byID[$0] }
        all = others
    }
}
