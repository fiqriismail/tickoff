import Foundation

/// A named group of tasks. Lives in `Shared/` because the sidebar, the task list and the edit
/// sheet all need it and features cannot import each other. Persistence is `ProjectStore`'s job.
struct Project: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String
    var colour: Accent
    var notes: String
    var archived: Bool
    /// The default project every task can fall back to; it can be neither deleted nor archived.
    var isInbox: Bool

    /// Inbox is seeded by migration `v2` with this id, which is also `tasks.project_id`'s default.
    static let inboxID: Int64 = 1
}

/// Why a project command was refused. The text is shown in the error banner.
enum ProjectError: LocalizedError, Equatable {
    case blankName
    case duplicateName(String)
    case inboxProtected
    case notFound

    var errorDescription: String? {
        switch self {
        case .blankName: "A project needs a name."
        case .duplicateName(let name): "A project named “\(name)” already exists."
        case .inboxProtected: "Inbox can’t be archived or deleted."
        case .notFound: "That project no longer exists."
        }
    }
}
