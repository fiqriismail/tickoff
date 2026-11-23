import Foundation
import FoundationModels

// The assistant's tools. Read tools answer from the workspace snapshot (no database queries); propose
// tools validate against it and record a `Proposal`. None of them can write: applying approved
// proposals is `ChangeBatch`'s job. They work unchanged with Apple's model and with MLX models.

// MARK: - Vocabulary

@Generable enum StatusChoice {
    case todo, inProgress, done

    var status: Status {
        switch self {
        case .todo: .todo
        case .inProgress: .inProgress
        case .done: .done
        }
    }
}

@Generable enum PriorityChoice {
    case low, medium, high

    var priority: Priority {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

@Generable enum GoalDirection { case up, down }

/// Small models don't call a tool whose arguments are empty (they print its name as the answer), so the
/// list tools take an optional name filter.
@Generable struct NameFilterArguments {
    @Guide(description: "Part of the name to look for; omit to list everything") var name: String?
}

// MARK: - Read tools

@Generable struct SearchTasksArguments {
    @Guide(description: "Words to find in the title or notes; omit to list everything") var query: String?
    @Guide(description: "Only tasks with this status") var status: StatusChoice?
    @Guide(description: "Only tasks in the project with this name") var project: String?
    @Guide(description: "Only tasks due before this date, YYYY-MM-DD") var dueBefore: String?
}

struct SearchTasksTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "search_tasks"
    let description = "Find tasks. Returns up to \(AssistantWorkspace.maxResults) tasks with their ids, status, priority, project and due date."

    func call(arguments a: SearchTasksArguments) async throws -> String {
        workspace.read { snapshot throws(ToolRefusal) in
            var project: Int64?
            if let name = a.project { project = try Resolve.project(name, in: snapshot).id }
            if let due = a.dueBefore { try Resolve.date(due) }
            var matches = snapshot.tasks.visible(status: a.status?.status, project: project, query: a.query ?? "")
            if let due = a.dueBefore { matches = matches.filter { !$0.due.isEmpty && $0.due < due } }
            if matches.isEmpty { return "No tasks match." }
            var lines: [String] = []
            var length = 0
            for task in matches.prefix(AssistantWorkspace.maxResults) {
                let line = Describe.line(task, in: snapshot)
                if length + line.count > AssistantWorkspace.maxCharacters - 100 { break }
                lines.append(line)
                length += line.count + 1
            }
            let footer = lines.count < matches.count
                ? "\nShowing \(lines.count) of \(matches.count) matching tasks; narrow the search to see the others."
                : ""
            return lines.joined(separator: "\n") + footer
        }
    }
}

@Generable struct GetTaskArguments {
    @Guide(description: "The task's id") var id: Int
}

struct GetTaskTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "get_task"
    let description = "Get one task by id, including its notes."

    func call(arguments a: GetTaskArguments) async throws -> String {
        workspace.read { snapshot throws(ToolRefusal) in
            let task = try Resolve.task(a.id, in: snapshot)
            let notes = task.notes.isEmpty ? "none" : String(task.notes.prefix(500))
            return Describe.line(task, in: snapshot) + "\nNotes: \(notes)"
        }
    }
}

struct ListProjectsTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "list_projects"
    let description = "List the projects with their ids, kinds and open task counts."

    func call(arguments: NameFilterArguments) async throws -> String {
        workspace.read { snapshot throws(ToolRefusal) in
            snapshot.projects.filter { Self.matches($0.name, arguments.name) }.map { project in
                if project.kind == .dailyGoals { return "\(project.name) (id \(project.id), daily goals)" }
                let open = snapshot.tasks.count(.todo, project: project.id)
                    + snapshot.tasks.count(.inProgress, project: project.id)
                return "\(project.name) (id \(project.id), \(open) open tasks)"
            }.joined(separator: "\n")
        }
    }
}

struct TodaysGoalsTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "todays_goals"
    let description = "List today's daily goals with their progress."

    func call(arguments: NameFilterArguments) async throws -> String {
        workspace.read { snapshot throws(ToolRefusal) in
            if snapshot.goals.isEmpty { return "There are no daily goals." }
            return snapshot.goals.filter { Self.matches($0.name, arguments.name) }.map { goal in
                goal.tracking == .checkOff
                    ? "\(goal.name): \(goal.value > 0 ? "done" : "not done") today"
                    : "\(goal.name): \(goal.value) of \(goal.target) today"
            }.joined(separator: "\n")
        }
    }
}

private extension FoundationModels.Tool {
    /// A missing or blank filter matches everything; otherwise a case-insensitive substring.
    static func matches(_ name: String, _ filter: String?) -> Bool {
        guard let filter = filter?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(filter)
    }
}

// MARK: - Propose tools

@Generable struct CreateTaskArguments {
    @Guide(description: "Short task title") var title: String
    @Guide(description: "Project name; omit for Inbox") var project: String?
    @Guide(description: "Omit unless the user said") var priority: PriorityChoice?
    @Guide(description: "Due date YYYY-MM-DD; omit if none") var due: String?
    @Guide(description: "Longer notes; omit if none") var notes: String?
}

struct CreateTaskTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "create_task"
    let description = "Propose a new task. Not created until the user approves."

    func call(arguments a: CreateTaskArguments) async throws -> String {
        workspace.propose { snapshot throws(ToolRefusal) in
            let title = try Resolve.title(a.title)
            let project = if let name = a.project { try Resolve.project(name, in: snapshot) } else { try Resolve.inbox(in: snapshot) }
            let priority = a.priority?.priority ?? .medium
            let due = if let text = a.due { try Resolve.date(text, allowEmpty: true) } else { "" }
            var summary = "Add “\(title)” to \(project.name)"
            if a.priority != nil { summary += ", \(priority.label.lowercased()) priority" }
            if !due.isEmpty { summary += ", due \(due)" }
            return (.addTask(title: title, priority: priority, projectID: project.id, notes: a.notes ?? "", due: due), summary)
        }
    }
}

@Generable struct UpdateTaskArguments {
    @Guide(description: "The task's id") var id: Int
    @Guide(description: "New title; omit to keep") var title: String?
    @Guide(description: "New notes; omit to keep") var notes: String?
    @Guide(description: "New priority; omit to keep") var priority: PriorityChoice?
    @Guide(description: "New due date YYYY-MM-DD, or an empty string to clear it; omit to keep") var due: String?
}

struct UpdateTaskTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "update_task"
    let description = "Propose changing a task's title, notes, priority or due date. Not changed until the user approves."

    func call(arguments a: UpdateTaskArguments) async throws -> String {
        workspace.propose { snapshot throws(ToolRefusal) in
            let task = try Resolve.task(a.id, in: snapshot)
            var title: String?
            if let text = a.title { title = try Resolve.title(text) }
            var due: String?
            if let text = a.due { due = try Resolve.date(text, allowEmpty: true) }
            guard title != nil || a.notes != nil || a.priority != nil || due != nil else {
                throw ToolRefusal("Nothing to change: give a new title, notes, priority or due date.")
            }
            var parts: [String] = []
            if let title { parts.append("title to “\(title)”") }
            if a.notes != nil { parts.append("notes") }
            if let priority = a.priority { parts.append("priority to \(priority.priority.label.lowercased())") }
            if let due { parts.append(due.isEmpty ? "clear the due date" : "due date to \(due)") }
            return (.editTask(id: task.id, title: title, notes: a.notes, priority: a.priority?.priority, due: due),
                    "Change “\(task.title)”: " + parts.joined(separator: ", "))
        }
    }
}

@Generable struct SetTaskStatusArguments {
    @Guide(description: "The task's id") var id: Int
    @Guide(description: "The new status") var status: StatusChoice
}

struct SetTaskStatusTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "set_task_status"
    let description = "Propose a new status for a task: todo, inProgress or done. Not changed until the user approves."

    func call(arguments a: SetTaskStatusArguments) async throws -> String {
        workspace.propose { snapshot throws(ToolRefusal) in
            let task = try Resolve.task(a.id, in: snapshot)
            guard task.status != a.status.status else {
                throw ToolRefusal("“\(task.title)” is already \(task.status.label).")
            }
            return (.setStatus(taskID: task.id, a.status.status), "Mark “\(task.title)” as \(a.status.status.label)")
        }
    }
}

@Generable struct SetStatusForMatchingArguments {
    @Guide(description: "Tasks whose title starts with this text") var titleStartsWith: String
    @Guide(description: "The new status") var status: StatusChoice
    @Guide(description: "Only this project's tasks; omit to use the project the conversation is about, or pass \"all\" for every project") var project: String?
}

struct SetStatusForMatchingTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "set_status_for_matching_tasks"
    let description = "Propose a new status for every task whose title starts with some text, optionally within one project. Use it for requests like \"close the tasks that start with Test\". Not changed until the user approves."

    func call(arguments a: SetStatusForMatchingArguments) async throws -> String {
        // Read outside the closure: it runs under the workspace's lock.
        let focus = workspace.focusProject
        return workspace.proposeMany { snapshot throws(ToolRefusal) in
            let prefix = a.titleStartsWith.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { throw ToolRefusal("Say what the titles start with.") }
            var scope: Int64?
            let named = a.project?.trimmingCharacters(in: .whitespaces) ?? ""
            let wanted = named.isEmpty ? focus : named
            if let wanted, !["all", "any", "every"].contains(wanted.lowercased()) {
                scope = try Resolve.project(wanted, in: snapshot).id
            }
            let target = a.status.status
            let matching = snapshot.tasks.items.filter { task in
                task.title.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                    && (scope == nil || task.projectID == scope) && task.status != target
            }
            guard !matching.isEmpty else {
                throw ToolRefusal("No task starting with “\(prefix)” needs to change to \(target.label).")
            }
            return matching.prefix(AssistantWorkspace.maxResults).map {
                (.setStatus(taskID: $0.id, target), "Mark “\($0.title)” as \(target.label)")
            }
        }
    }
}

@Generable struct MoveTaskArguments {
    @Guide(description: "The task's id") var id: Int
    @Guide(description: "Name of the destination project") var project: String
}

struct MoveTaskTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "move_task"
    let description = "Propose moving a task to another project. Not moved until the user approves."

    func call(arguments a: MoveTaskArguments) async throws -> String {
        workspace.propose { snapshot throws(ToolRefusal) in
            let task = try Resolve.task(a.id, in: snapshot)
            let project = try Resolve.project(a.project, in: snapshot)
            guard task.projectID != project.id else { throw ToolRefusal("“\(task.title)” is already in \(project.name).") }
            return (.moveTask(id: task.id, toProject: project.id), "Move “\(task.title)” to \(project.name)")
        }
    }
}

@Generable struct DeleteTaskArguments {
    @Guide(description: "The task's id") var id: Int
}

struct DeleteTaskTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "delete_task"
    let description = "Propose deleting a task. Not deleted until the user approves."

    func call(arguments a: DeleteTaskArguments) async throws -> String {
        workspace.propose { snapshot throws(ToolRefusal) in
            let task = try Resolve.task(a.id, in: snapshot)
            return (.deleteTask(id: task.id), "Delete “\(task.title)”")
        }
    }
}

@Generable struct ChangeGoalProgressArguments {
    @Guide(description: "Name of one of today's daily goals") var goal: String
    @Guide(description: "up to add progress (or check it off), down to remove it") var direction: GoalDirection
}

struct ChangeGoalProgressTool: FoundationModels.Tool {
    let workspace: AssistantWorkspace
    let name = "change_goal_progress"
    let description = "Propose adding or removing one unit of today's progress on a daily goal. Not changed until the user approves."

    func call(arguments a: ChangeGoalProgressArguments) async throws -> String {
        workspace.propose { snapshot throws(ToolRefusal) in
            guard let goal = snapshot.goal(named: a.goal) else {
                let names = snapshot.goals.map(\.name).joined(separator: ", ")
                throw ToolRefusal("No daily goal named “\(a.goal)”. Today's goals: \(names.isEmpty ? "none" : names).")
            }
            let up = a.direction == .up
            let summary: String
            if goal.tracking == .checkOff {
                if up && goal.value > 0 { throw ToolRefusal("“\(goal.name)” is already done today.") }
                if !up && goal.value == 0 { throw ToolRefusal("“\(goal.name)” is not done today, so there is nothing to undo.") }
                summary = up ? "Check off “\(goal.name)”" : "Uncheck “\(goal.name)”"
            } else {
                if !up && goal.value == 0 { throw ToolRefusal("“\(goal.name)” is already at 0 today.") }
                summary = up ? "Add one to “\(goal.name)” (\(goal.value + 1) of \(goal.target))"
                    : "Remove one from “\(goal.name)” (\(goal.value - 1) of \(goal.target))"
            }
            return (.changeGoalProgress(goalID: goal.goal.id, increment: up), summary)
        }
    }
}

// MARK: - Shared helpers

enum AssistantTools {
    /// Every tool, for `LanguageModelSession(model:tools:instructions:)`.
    static func all(_ workspace: AssistantWorkspace) -> [any FoundationModels.Tool] {
        [
            SearchTasksTool(workspace: workspace), GetTaskTool(workspace: workspace),
            ListProjectsTool(workspace: workspace), TodaysGoalsTool(workspace: workspace),
            CreateTaskTool(workspace: workspace), UpdateTaskTool(workspace: workspace),
            SetTaskStatusTool(workspace: workspace), SetStatusForMatchingTool(workspace: workspace),
            MoveTaskTool(workspace: workspace),
            DeleteTaskTool(workspace: workspace), ChangeGoalProgressTool(workspace: workspace),
        ]
    }
}

/// Looks things up in a snapshot, refusing with a message that tells the model how to recover.
private enum Resolve {
    static func task(_ id: Int, in snapshot: AssistantSnapshot) throws(ToolRefusal) -> Task {
        guard let task = snapshot.task(id) else {
            throw ToolRefusal("No task has id \(id). Use search_tasks to find the right id.")
        }
        return task
    }

    static func project(_ name: String, in snapshot: AssistantSnapshot) throws(ToolRefusal) -> Project {
        guard let project = snapshot.project(named: name) else {
            let names = snapshot.taskProjects.map(\.name).joined(separator: ", ")
            throw ToolRefusal("No task project named “\(name)”. Projects: \(names).")
        }
        return project
    }

    static func inbox(in snapshot: AssistantSnapshot) throws(ToolRefusal) -> Project {
        guard let inbox = snapshot.taskProjects.first(where: \.isInbox) else {
            throw ToolRefusal("There is no Inbox; name a project.")
        }
        return inbox
    }

    static func title(_ title: String) throws(ToolRefusal) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ToolRefusal("A task needs a title.") }
        return trimmed
    }

    /// A real calendar day as YYYY-MM-DD; "" is allowed where it means "no date".
    @discardableResult
    static func date(_ text: String, allowEmpty: Bool = false) throws(ToolRefusal) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty && allowEmpty { return "" }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard trimmed.count == 10, parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2],
            let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
            calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: y, month: m, day: d)
        else { throw ToolRefusal("“\(text)” is not a date. Use YYYY-MM-DD, for example 2026-12-31.") }
        return trimmed
    }
}

private enum Describe {
    static func line(_ task: Task, in snapshot: AssistantSnapshot) -> String {
        let project = snapshot.projects.first { $0.id == task.projectID }?.name ?? "Unknown project"
        let due = task.due.isEmpty ? "" : ", due \(task.due)"
        return "#\(task.id) “\(task.title)” (\(task.status.label), \(task.priority.label.lowercased()) priority, \(project)\(due))"
    }
}
