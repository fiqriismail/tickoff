import Foundation
import FoundationModels
import Testing

@testable import Tickoff

struct AssistantToolsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func project(_ id: Int64, _ name: String, kind: ProjectKind = .tasks) -> Project {
        Project(id: id, name: name, colour: .system, notes: "", archived: false, isInbox: id == 1, kind: kind)
    }

    private func task(
        _ id: Int64, _ title: String, project: Int64 = 1, status: Status = .todo, priority: Priority = .medium,
        due: String = "", notes: String = ""
    ) -> Task {
        Task(id: id, title: title, notes: notes, priority: priority, status: status, due: due, projectID: project)
    }

    private func goal(_ id: Int64, _ name: String, _ tracking: GoalTracking, target: Int = 1, value: Int = 0) -> GoalDay {
        GoalDay(
            goal: DailyGoal(id: id, projectID: 9, name: name, tracking: tracking, target: target),
            day: "2026-11-20", name: name, tracking: tracking, target: target, value: value)
    }

    /// Friday 20 November 2026 with a small, known data set.
    private func workspace(extraTasks: [Task] = []) -> AssistantWorkspace {
        var tasks = TaskSet()
        tasks.replace(
            [
                task(1, "Buy groceries"),
                task(2, "Write quarterly report", project: 2, status: .inProgress, priority: .high, due: "2026-11-25", notes: "Q4 numbers"),
                task(3, "Call dentist", due: "2026-11-18"),
                task(4, "Fix login bug", project: 2),
                task(5, "Book flights", project: 3, status: .done),
            ] + extraTasks)
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        return AssistantWorkspace(
            snapshot: AssistantSnapshot(
                tasks: tasks,
                projects: [project(1, "Inbox"), project(2, "Work"), project(3, "Personal"), project(9, "Health", kind: .dailyGoals)],
                goals: [goal(1, "Meditate", .checkOff), goal(2, "Drink water", .counter, target: 8, value: 3)],
                today: today, calendar: calendar))
    }

    // MARK: Bulk status

    @Test func closingTasksByTitlePrefixOnlyTouchesTheNamedProjectAndSkipsDoneOnes() async throws {
        let w = workspace(extraTasks: [
            task(10, "Test one"), task(11, "test two"), task(12, "Test three", project: 2),
            task(13, "Test four", status: .done), task(14, "Retest it"),
        ])
        let tool = SetStatusForMatchingTool(workspace: w)
        let reply = try await tool.call(arguments: .init(titleStartsWith: "Test", status: .done, project: "inbox"))
        #expect(reply.contains("#1:") && reply.contains("#2:") && !reply.contains("#3"))
        #expect(w.proposals.map(\.change) == [.setStatus(taskID: 10, .done), .setStatus(taskID: 11, .done)])
    }

    @Test func theConversationsProjectIsTheDefaultScopeAndAllOverridesIt() async throws {
        let w = workspace(extraTasks: [task(10, "Test one"), task(12, "Test three", project: 2)])
        w.focusProject = "Inbox"
        let tool = SetStatusForMatchingTool(workspace: w)
        _ = try await tool.call(arguments: .init(titleStartsWith: "Test", status: .done))
        #expect(w.proposals.map(\.change) == [.setStatus(taskID: 10, .done)])
        _ = try await tool.call(arguments: .init(titleStartsWith: "Test", status: .done, project: "all"))
        #expect(w.proposals.count == 3)
    }

    @Test func closingTasksWithoutAProjectSpansEveryProjectAndNoMatchIsAnError() async throws {
        let w = workspace(extraTasks: [task(10, "Test one"), task(12, "Test three", project: 2)])
        let tool = SetStatusForMatchingTool(workspace: w)
        _ = try await tool.call(arguments: .init(titleStartsWith: "Test", status: .done))
        #expect(w.proposals.count == 2)
        let none = try await tool.call(arguments: .init(titleStartsWith: "Zzz", status: .done))
        #expect(none.hasPrefix("Error:") && w.proposals.count == 2)
        let unknown = try await tool.call(arguments: .init(titleStartsWith: "Test", status: .done, project: "Nope"))
        #expect(unknown.hasPrefix("Error:"))
    }

    // MARK: Read tools

    @Test func searchFiltersByTextStatusProjectAndDueDate() async throws {
        let w = workspace()
        let search = SearchTasksTool(workspace: w)
        let text = try await search.call(arguments: .init(query: "REPORT"))
        #expect(text.contains("#2") && !text.contains("#1 "))
        let open = try await search.call(arguments: .init(status: .inProgress))
        #expect(open.contains("#2") && !open.contains("#4"))
        let work = try await search.call(arguments: .init(project: " work "))
        #expect(work.contains("#2") && work.contains("#4") && !work.contains("#1 "))
        let overdue = try await search.call(arguments: .init(dueBefore: "2026-11-20"))
        #expect(overdue.contains("#3") && !overdue.contains("#2"))
        #expect(try await search.call(arguments: .init(query: "zzz")) == "No tasks match.")
    }

    @Test func searchResultsAreCappedAndSaySoWithoutLeakingTheRest() async throws {
        let many = (100..<400).map { task(Int64($0), "Bulk task \($0)") }
        let w = workspace(extraTasks: many)
        let text = try await SearchTasksTool(workspace: w).call(arguments: .init(query: "bulk"))
        #expect(text.split(separator: "\n").count <= AssistantWorkspace.maxResults + 1)
        #expect(text.contains("of 300 matching tasks"))
        #expect(text.count <= AssistantWorkspace.maxCharacters)
    }

    @Test func searchRefusesAnUnknownProjectAndABadDate() async throws {
        let search = SearchTasksTool(workspace: workspace())
        let project = try await search.call(arguments: .init(project: "Nowhere"))
        #expect(project.hasPrefix("Error:") && project.contains("Inbox, Work, Personal"))
        let date = try await search.call(arguments: .init(dueBefore: "2026-02-30"))
        #expect(date.hasPrefix("Error:") && date.contains("YYYY-MM-DD"))
    }

    @Test func getTaskReturnsDetailsAndNotesOrAHelpfulError() async throws {
        let get = GetTaskTool(workspace: workspace())
        let found = try await get.call(arguments: .init(id: 2))
        #expect(found.contains("Write quarterly report") && found.contains("In Progress") && found.contains("Q4 numbers"))
        let missing = try await get.call(arguments: .init(id: 99))
        #expect(missing.hasPrefix("Error:") && missing.contains("search_tasks"))
    }

    @Test func listProjectsAndTodaysGoalsSummariseTheSnapshot() async throws {
        let w = workspace()
        let projects = try await ListProjectsTool(workspace: w).call(arguments: NameFilterArguments(name: nil))
        #expect(projects.contains("Work (id 2, 2 open tasks)") && projects.contains("Health (id 9, daily goals)"))
        let goals = try await TodaysGoalsTool(workspace: w).call(arguments: NameFilterArguments(name: nil))
        #expect(goals.contains("Meditate: not done today") && goals.contains("Drink water: 3 of 8 today"))
    }

    // MARK: Propose tools

    @Test func createTaskProposesWithDefaultsAndOptionalFields() async throws {
        let w = workspace()
        let create = CreateTaskTool(workspace: w)
        let plain = try await create.call(arguments: .init(title: "  Buy milk "))
        #expect(plain.hasPrefix("Proposed #1"))
        let rich = try await create.call(arguments: .init(
            title: "Prepare slides", project: "work", priority: .high, due: "2026-12-01", notes: "for Monday"))
        #expect(rich.hasPrefix("Proposed #2"))
        #expect(w.proposals.map(\.change) == [
            .addTask(title: "Buy milk", priority: .medium, projectID: 1),
            .addTask(title: "Prepare slides", priority: .high, projectID: 2, notes: "for Monday", due: "2026-12-01"),
        ])
    }

    @Test func createTaskRefusesBlankTitlesUnknownProjectsDailyGoalProjectsAndBadDates() async throws {
        let w = workspace()
        let create = CreateTaskTool(workspace: w)
        for arguments: CreateTaskArguments in [
            .init(title: "  "), .init(title: "x", project: "Nowhere"), .init(title: "x", project: "Health"),
            .init(title: "x", due: "next friday"),
        ] {
            #expect(try await create.call(arguments: arguments).hasPrefix("Error:"))
        }
        #expect(w.proposals.isEmpty)
    }

    @Test func updateTaskProposesOnlyTheGivenFieldsAndCanClearTheDueDate() async throws {
        let w = workspace()
        let update = UpdateTaskTool(workspace: w)
        #expect(try await update.call(arguments: .init(id: 3, due: "")).hasPrefix("Proposed #1"))
        #expect(try await update.call(arguments: .init(id: 4, title: "Fix sign-in bug", priority: .low)).hasPrefix("Proposed #2"))
        #expect(w.proposals.map(\.change) == [
            .editTask(id: 3, due: ""),
            .editTask(id: 4, title: "Fix sign-in bug", priority: .low),
        ])
        #expect(try await update.call(arguments: .init(id: 4)).contains("Nothing to change"))
        #expect(try await update.call(arguments: .init(id: 99, title: "x")).hasPrefix("Error:"))
        #expect(try await update.call(arguments: .init(id: 4, due: "31/12/2026")).hasPrefix("Error:"))
    }

    @Test func setStatusMoveAndDeleteValidateAgainstTheCurrentData() async throws {
        let w = workspace()
        let status = SetTaskStatusTool(workspace: w)
        let move = MoveTaskTool(workspace: w)
        let delete = DeleteTaskTool(workspace: w)
        #expect(try await status.call(arguments: .init(id: 3, status: .done)).hasPrefix("Proposed #1"))
        #expect(try await status.call(arguments: .init(id: 5, status: .done)).contains("already Done"))
        #expect(try await move.call(arguments: .init(id: 4, project: "Personal")).hasPrefix("Proposed #2"))
        #expect(try await move.call(arguments: .init(id: 4, project: "Work")).contains("already in Work"))
        #expect(try await move.call(arguments: .init(id: 4, project: "Health")).hasPrefix("Error:"))
        #expect(try await delete.call(arguments: .init(id: 1)).hasPrefix("Proposed #3"))
        #expect(try await delete.call(arguments: .init(id: 42)).hasPrefix("Error:"))
        #expect(w.proposals.map(\.change) == [.setStatus(taskID: 3, .done), .moveTask(id: 4, toProject: 3), .deleteTask(id: 1)])
    }

    @Test func goalProgressRespectsCounterAndCheckOffRules() async throws {
        let w = workspace()
        let progress = ChangeGoalProgressTool(workspace: w)
        #expect(try await progress.call(arguments: .init(goal: "drink WATER", direction: .up)).contains("4 of 8"))
        #expect(try await progress.call(arguments: .init(goal: "Meditate", direction: .up)).hasPrefix("Proposed"))
        #expect(try await progress.call(arguments: .init(goal: "Meditate", direction: .down)).contains("nothing to undo"))
        let unknown = try await progress.call(arguments: .init(goal: "Yoga", direction: .up))
        #expect(unknown.hasPrefix("Error:") && unknown.contains("Meditate, Drink water"))
        #expect(w.proposals.map(\.change) == [
            .changeGoalProgress(goalID: 2, increment: true), .changeGoalProgress(goalID: 1, increment: true),
        ])
    }

    @Test func proposalsCanBeDiscardedAndKeepTheirNumbers() async throws {
        let w = workspace()
        let delete = DeleteTaskTool(workspace: w)
        _ = try await delete.call(arguments: .init(id: 1))
        _ = try await delete.call(arguments: .init(id: 3))
        w.discardProposal(id: 1)
        #expect(w.proposals.map(\.id) == [2])
        _ = try await delete.call(arguments: .init(id: 4))
        #expect(w.proposals.map(\.id) == [2, 3])
        w.discardAllProposals()
        #expect(w.proposals.isEmpty)
    }

    @Test func toolsNeverWriteToTheDatabase() async throws {
        let database = try AppDatabase()
        let store = TaskStore(database: database)
        let id = try store.insert(title: "keep me", priority: .medium)
        var tasks = TaskSet()
        tasks.replace(try store.loadAll())
        let w = AssistantWorkspace(
            snapshot: AssistantSnapshot(tasks: tasks, projects: [project(1, "Inbox")], goals: []))
        _ = try await DeleteTaskTool(workspace: w).call(arguments: .init(id: Int(id)))
        _ = try await SetTaskStatusTool(workspace: w).call(arguments: .init(id: Int(id), status: .done))
        _ = try await CreateTaskTool(workspace: w).call(arguments: .init(title: "new"))
        #expect(w.proposals.count == 3)
        #expect(try store.loadAll().map(\.title) == ["keep me"])
        #expect(try store.loadAll().first?.status == .todo)
    }

    @Test func updatingTheSnapshotChangesWhatLaterCallsSee() async throws {
        let w = workspace()
        let get = GetTaskTool(workspace: w)
        #expect(try await get.call(arguments: .init(id: 1)).contains("Buy groceries"))
        var snapshot = w.snapshot
        snapshot.tasks.replace([])
        w.update(snapshot)
        #expect(try await get.call(arguments: .init(id: 1)).hasPrefix("Error:"))
    }

    // MARK: Instructions

    @Test func instructionsCarryTheDateVocabularyAndIds() {
        let text = AssistantWorkspace.instructions(for: workspace().snapshot)
        #expect(text.contains("Friday 2026-11-20"))
        #expect(text.contains("todo, inProgress, done") && text.contains("low, medium, high"))
        #expect(text.contains("Inbox (id 1), Work (id 2), Personal (id 3)"))
        #expect(!text.contains("Health"))
        #expect(text.contains("Meditate, Drink water"))
        #expect(text.contains("Never invent ids"))
    }

    // MARK: A real session with a scripted model (no weights)

    @Test func aScriptedModelCallIsRecordedAsAProposalThroughARealSession() async throws {
        guard #available(macOS 27.0, *) else { return }
        let w = workspace()
        let model = ScriptedLanguageModel(
            toolName: "move_task", arguments: #"{"id": 4, "project": "Personal"}"#, reply: "I've proposed moving it.")
        let session = LanguageModelSession(
            model: model, tools: AssistantTools.all(w), instructions: AssistantWorkspace.instructions(for: w.snapshot))
        let response = try await session.respond(to: "Move the login bug to Personal")
        #expect(response.content == "I've proposed moving it.")
        #expect(w.proposals.map(\.change) == [.moveTask(id: 4, toProject: 3)])
        #expect(w.proposals.first?.summary == "Move “Fix login bug” to Personal")
    }
}
