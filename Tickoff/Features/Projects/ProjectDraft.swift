import Foundation

/// The project sheet's working copy. Validation lives here so it can be tested without a view;
/// uniqueness is the store's call, since only it can see the other projects.
struct ProjectDraft: Equatable {
    /// `nil` while creating.
    var id: Int64?
    var name: String
    var colour: ProjectColour
    var notes: String
    var archived: Bool
    var isInbox: Bool

    /// A blank draft for "New Project".
    init() {
        name = ""
        colour = .system
        notes = ""
        archived = false
        isInbox = false
    }

    init(project: Project) {
        id = project.id
        name = project.name
        colour = project.colour
        notes = project.notes
        archived = project.archived
        isInbox = project.isInbox
    }

    /// The project to save, with the name trimmed; a blank name is refused.
    func validated() throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProjectError.blankName }
        return Project(
            id: id ?? 0, name: trimmed, colour: colour, notes: notes, archived: archived,
            isInbox: isInbox)
    }
}
