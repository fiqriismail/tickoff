import Foundation
import Synchronization

/// What the assistant may see: an immutable copy of the shell's data, taken before each turn so the
/// tools never query the database or touch main-actor state.
struct AssistantSnapshot: Sendable {
    var tasks: TaskSet
    /// Non-archived projects of both kinds.
    var projects: [Project]
    var goals: [GoalDay]
    var today: Date
    var calendar: Calendar

    init(tasks: TaskSet, projects: [Project], goals: [GoalDay], today: Date = .now, calendar: Calendar = .current) {
        self.tasks = tasks
        self.projects = projects
        self.goals = goals
        self.today = today
        self.calendar = calendar
    }

    var taskProjects: [Project] { projects.filter { $0.kind == .tasks } }

    func project(named name: String) -> Project? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return taskProjects.first { $0.name.lowercased() == wanted }
    }

    func task(_ id: Int) -> Task? { tasks.items.first { $0.id == Int64(id) } }

    func goal(named name: String) -> GoalDay? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return goals.first { $0.name.lowercased() == wanted }
    }
}

/// Why a tool call was refused. The text goes back to the model, so it says how to recover.
struct ToolRefusal: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// The shared state behind the assistant's tools: the current snapshot and the proposals recorded so
/// far. Thread-safe because tools run off the main actor; it holds no database handle, so nothing
/// here can write.
final class AssistantWorkspace: Sendable {
    /// Most tasks a search returns, and the most characters in any tool reply. Apple's model has a
    /// small context window, and 10,000 tasks must never flood it.
    static let maxResults = 20
    static let maxCharacters = 2_000

    private struct State {
        var snapshot: AssistantSnapshot
        var proposals: [Proposal] = []
        var nextID = 1
        var focusProject: String?
    }

    private let state: Mutex<State>

    init(snapshot: AssistantSnapshot) {
        state = Mutex(State(snapshot: snapshot))
    }

    var snapshot: AssistantSnapshot { state.withLock { $0.snapshot } }
    var proposals: [Proposal] { state.withLock { $0.proposals } }

    /// The project the conversation is about; tools that take an optional project fall back to it.
    var focusProject: String? {
        get { state.withLock { $0.focusProject } }
        set { state.withLock { $0.focusProject = newValue } }
    }

    /// Refreshes what the tools see (data changed, or a day passed); recorded proposals stay.
    func update(_ snapshot: AssistantSnapshot) {
        state.withLock { $0.snapshot = snapshot }
    }

    func discardProposal(id: Int) {
        state.withLock { $0.proposals.removeAll { $0.id == id } }
    }

    func discardAllProposals() {
        state.withLock { $0.proposals = [] }
    }

    /// Runs a read-only tool; a refusal becomes an "Error: …" reply the model can act on.
    func read(_ work: (AssistantSnapshot) throws(ToolRefusal) -> String) -> String {
        let snapshot = state.withLock { $0.snapshot }
        do throws(ToolRefusal) { return Self.capped(try work(snapshot)) } catch { return "Error: \(error.message)" }
    }

    /// Validates a change against the current snapshot and records it, or replies with why not.
    func propose(_ make: (AssistantSnapshot) throws(ToolRefusal) -> (change: ProposedChange, summary: String)) -> String {
        state.withLock { state in
            do throws(ToolRefusal) {
                let made = try make(state.snapshot)
                let proposal = Proposal(id: state.nextID, change: made.change, summary: made.summary)
                state.nextID += 1
                state.proposals.append(proposal)
                return "Proposed #\(proposal.id): \(made.summary). The user must approve it before anything changes."
            } catch {
                return "Error: \(error.message)"
            }
        }
    }

    /// Like `propose`, for a change that touches several tasks: one proposal per task, all or nothing.
    func proposeMany(
        _ make: (AssistantSnapshot) throws(ToolRefusal) -> [(change: ProposedChange, summary: String)]
    ) -> String {
        state.withLock { state in
            do throws(ToolRefusal) {
                let made = try make(state.snapshot)
                var ids: [Int] = []
                for item in made {
                    state.proposals.append(Proposal(id: state.nextID, change: item.change, summary: item.summary))
                    ids.append(state.nextID)
                    state.nextID += 1
                }
                let lines = zip(ids, made).map { "Proposed #\($0): \($1.summary)" }.joined(separator: "\n")
                return Self.capped(lines + "\nThe user must approve these before anything changes.")
            } catch {
                return "Error: \(error.message)"
            }
        }
    }

    private static func capped(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters)) + "\n…(reply shortened)"
    }

    /// The system instructions for a session: the date, vocabulary and the ids the model may use.
    static func instructions(for snapshot: AssistantSnapshot) -> String {
        let day = GoalDate.key(for: snapshot.today, calendar: snapshot.calendar)
        let weekday = snapshot.today.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        let projects = snapshot.taskProjects.prefix(30).map { "\($0.name) (id \($0.id))" }.joined(separator: ", ")
        let goals = snapshot.goals.prefix(30).map(\.name).joined(separator: ", ")
        return """
            You help the user manage their tasks in Tickoff. Today is \(weekday) \(day).
            Use the tools to look things up and to propose changes. Propose a change only when the \
            user asks for one in their latest message. A question (how many, which, what is due) \
            gets an answer in words, never a proposal: call search_tasks or list_projects right away \
            (do not say "I'll check" or "let me look"; call the tool instead) and answer from what it \
            returns. Nothing \
            changes until the user approves a proposal, so say "I've proposed …", never "done". Never invent ids: find a task's \
            id with search_tasks or get_task first, searching for a few words of its title (not its \
            status). To change a task, call the matching propose tool once for each task (several tasks \
            means several calls); only say you proposed something \
            after a tool replied "Proposed #n". If a tool replies with an error, fix the arguments \
            and try again, or ask the user.
            "Close", "finish" or "complete" tasks means status done: for tasks picked by the start of their \
            title ("the tasks that start with Test") call set_status_for_matching_tasks once, passing the \
            project the user named (use the earlier conversation to know which); otherwise set_task_status; only propose \
            delete_task when the user says delete or remove. When the user names a project, search only \
            that project (the project argument of search_tasks).
            Statuses: todo, inProgress, done. Priorities: low, medium, high. Dates are YYYY-MM-DD.
            Task projects: \(projects.isEmpty ? "none" : projects).
            Daily goals today: \(goals.isEmpty ? "none" : goals).
            """
    }
}
