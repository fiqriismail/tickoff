import Foundation
import SwiftUI

/// A named group of tasks. Lives in `Shared/` because the sidebar, the task list and the edit
/// sheet all need it and features cannot import each other. Persistence is `ProjectStore`'s job.
struct Project: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String
    var colour: ProjectColour
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

/// Which projects the shell is showing: all of them, or one. In memory only.
enum ProjectScope: Hashable, Sendable {
    case all
    case project(Int64)

    /// The project id this scope selects, or `nil` for all projects.
    var projectID: Int64? {
        switch self {
        case .all: nil
        case .project(let id): id
        }
    }
}

/// A project's colour. The raw keys are what `projects.colour` already stores, so they must never
/// change; the colours themselves are system colours that adapt to light and dark.
enum ProjectColour: String, CaseIterable, Sendable {
    case system, indigo, violet, teal, rose, orange

    var label: String {
        switch self {
        case .system: "Accent"
        case .indigo: "Indigo"
        case .violet: "Purple"
        case .teal: "Teal"
        case .rose: "Pink"
        case .orange: "Orange"
        }
    }

    /// The value stored in `projects.colour`.
    var key: String { rawValue }

    init?(key: String) { self.init(rawValue: key) }

    /// `.system` follows the accent chosen in System Settings.
    var color: Color {
        switch self {
        case .system: .accentColor
        case .indigo: .indigo
        case .violet: .purple
        case .teal: .teal
        case .rose: .pink
        case .orange: .orange
        }
    }
}
