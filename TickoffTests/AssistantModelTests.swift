import Foundation
import FoundationModels
import Testing

@testable import Tickoff

@MainActor
struct AssistantModelTests {
    private final class Reports2 { var instructions: [String] = [] }
    private final class Reports { var outcomes: [Outcome] = []; var savedKeys: [String] = [] }

    private struct Fixture {
        let database: AppDatabase
        let tasks: TaskStore
        let projects: ProjectStore
        let reports: Reports
        let model: AssistantModel
        let first: Int64
    }

    private func fixture(
        toolName: String = "set_task_status", arguments: String? = nil, delay: Duration = .zero,
        storedKey: String? = nil, macOS27: Bool = true, claimsWithoutTool: Bool = false,
        factory: AssistantModel.SessionFactory? = nil
    ) throws -> Fixture {
        let database = try AppDatabase()
        let tasks = TaskStore(database: database)
        let projects = ProjectStore(database: database)
        let first = try tasks.insert(title: "Buy groceries", priority: .medium)
        try tasks.insert(title: "Call dentist", priority: .medium)
        let reports = Reports()
        let storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-am-\(UUID().uuidString)"))
        let hardware = HardwareProfile(
            chipName: "Apple M3 Pro", memoryBytes: 24 << 30, gpuBudgetBytes: 16 << 30, freeDiskBytes: 200 << 30)
        let provider = ModelProvider(storage: storage, hardware: hardware)
        let args = arguments ?? #"{"id": \#(first), "status": "done"}"#
        let model = AssistantModel(
            provider: provider,
            snapshot: {
                var set = TaskSet()
                set.replace((try? tasks.loadAll()) ?? [])
                return AssistantSnapshot(tasks: set, projects: (try? projects.loadAll()) ?? [], goals: [])
            },
            batch: ChangeBatch(database: database), report: { reports.outcomes.append($0) },
            storedChoiceKey: storedKey, saveChoiceKey: { reports.savedKeys.append($0) },
            runsOnMacOS27OrLater: macOS27,
            makeSession: factory ?? { _, tools, instructions in
                guard #available(macOS 27.0, *) else { throw ModelAccessError.unavailable("needs 27") }
                let scripted = ScriptedLanguageModel(
                    toolName: toolName, arguments: args, reply: "I’ve proposed that.", delay: delay,
                    claimsWithoutTool: claimsWithoutTool)
                return LanguageModelSession(model: scripted, tools: tools, instructions: instructions)
            })
        return Fixture(database: database, tasks: tasks, projects: projects, reports: reports, model: model, first: first)
    }

    private func waitUntilIdle(_ model: AssistantModel, timeout: Duration = .seconds(5)) async {
        let start = ContinuousClock.now
        while model.isBusy, ContinuousClock.now - start < timeout {
            try? await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aQuestionStreamsAReplyAndRecordsAProposalWithoutChangingAnything() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture()
        f.model.send("  Mark the groceries as done  ")
        await waitUntilIdle(f.model)
        #expect(f.model.status == .idle)
        #expect(f.model.messages.map(\.text) == ["Mark the groceries as done", "I’ve proposed that."])
        #expect(f.model.messages.map(\.role) == [.user, .assistant])
        #expect(f.model.proposals.map(\.summary) == ["Mark “Buy groceries” as Done"])
        #expect(try f.tasks.loadAll().first { $0.id == f.first }?.status == .todo)
        #expect(f.reports.outcomes.isEmpty)
    }

    @Test func aClaimedProposalWithoutAToolCallIsCorrectedOnceSoTheProposalExists() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture(claimsWithoutTool: true)
        f.model.send("Mark the groceries as done")
        await waitUntilIdle(f.model)
        #expect(f.model.status == .idle)
        #expect(f.model.proposals.map(\.summary) == ["Mark “Buy groceries” as Done"])
        #expect(f.model.messages.count == 2)
    }

    @Test func eachMessageStartsAFreshSessionThatCarriesTheConversationButNotProposalWording() async throws {
        guard #available(macOS 27.0, *) else { return }
        let seen = Reports2()
        let f = try fixture(factory: { _, tools, instructions in
            seen.instructions.append(instructions)
            let scripted = ScriptedLanguageModel(
                toolName: "set_task_status", arguments: #"{"id": 1, "status": "done"}"#, reply: "I’ve proposed that.")
            return LanguageModelSession(model: scripted, tools: tools, instructions: instructions)
        })
        f.model.send("Close the groceries task")
        await waitUntilIdle(f.model)
        f.model.send("How many tasks are in the inbox?")
        await waitUntilIdle(f.model)
        #expect(seen.instructions.count == 2)
        #expect(!seen.instructions[0].contains("The conversation so far"))
        #expect(seen.instructions[1].contains("User: Close the groceries task"))
        #expect(seen.instructions[1].contains("Tickoff: (a change was put forward for the user to approve)"))
        #expect(!seen.instructions[1].contains("I’ve proposed that."))
    }

    @Test func applyingAProposalWritesItThroughTheBatchAndReportsChanged() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture()
        f.model.send("Mark the groceries as done")
        await waitUntilIdle(f.model)
        f.model.apply(try #require(f.model.proposals.first))
        #expect(f.reports.outcomes == [.changed])
        #expect(f.model.proposals.isEmpty)
        #expect(try f.tasks.loadAll().first { $0.id == f.first }?.status == .done)
    }

    @Test func aProposalGoneStaleFailsCleanlyAndStaysForTheUserToDiscard() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture()
        f.model.send("Mark the groceries as done")
        await waitUntilIdle(f.model)
        try f.tasks.delete(id: f.first)
        f.model.applyAll()
        #expect(f.reports.outcomes == [.failed(ChangeError.taskNotFound(f.first).localizedDescription)])
        #expect(f.model.proposals.count == 1)
        f.model.discardAll()
        #expect(f.model.proposals.isEmpty)
    }

    @Test func discardingOneProposalLeavesTheOthers() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture()
        f.model.send("one")
        await waitUntilIdle(f.model)
        f.model.send("two")
        await waitUntilIdle(f.model)
        #expect(f.model.proposals.map(\.id) == [1, 2])
        f.model.discard(f.model.proposals[0])
        #expect(f.model.proposals.map(\.id) == [2])
    }

    @Test func aFailedSessionShowsTheReasonAndKeepsTheUsersMessage() async throws {
        let f = try fixture(factory: { _, _, _ in throw ModelAccessError.notDownloaded })
        f.model.send("hello")
        await waitUntilIdle(f.model)
        #expect(f.model.status == .failed(ModelAccessError.notDownloaded.localizedDescription))
        #expect(f.model.messages.map(\.text) == ["hello"])
        #expect(!f.model.isBusy)
    }

    @Test func stopCancelsASlowAnswerAndLeavesNoEmptyBubble() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture(delay: .seconds(30))
        let start = ContinuousClock.now
        f.model.send("slow one")
        while f.model.status != .responding { try await _Concurrency.Task.sleep(for: .milliseconds(20)) }
        f.model.stop()
        await waitUntilIdle(f.model)
        #expect(f.model.status == .idle)
        #expect(f.model.messages.map(\.text) == ["slow one"])
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func aNewConversationClearsTheTranscriptAndProposals() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture()
        f.model.send("Mark the groceries as done")
        await waitUntilIdle(f.model)
        f.model.newConversation()
        #expect(f.model.messages.isEmpty && f.model.proposals.isEmpty && f.model.status == .idle)
    }

    @Test func emptyAndWhitespaceMessagesAreIgnoredAndASecondMessageWaitsForTheFirst() async throws {
        guard #available(macOS 27.0, *) else { return }
        let f = try fixture(delay: .milliseconds(200))
        f.model.send("   ")
        #expect(f.model.messages.isEmpty)
        f.model.send("first")
        f.model.send("second")
        #expect(f.model.messages.map(\.text) == ["first", ""])
        f.model.stop()
        await waitUntilIdle(f.model)
    }

    @Test func theChoiceStartsFromTheStoredKeyAndFallsBackToAppleWhenUnusable() throws {
        #expect(try fixture(storedKey: "balanced").model.choice == .balanced)
        #expect(try fixture(storedKey: "balanced", macOS27: false).model.choice == .apple)
        #expect(try fixture(storedKey: "nonsense").model.choice == .apple)
        #expect(try fixture().model.choice == .apple)
    }

    @Test func selectingAModelSavesItsKeyOnlyWhenTheOSOffersIt() throws {
        let modern = try fixture()
        modern.model.select(.small)
        #expect(modern.model.choice == .small && modern.reports.savedKeys == ["small"])
        let legacy = try fixture(macOS27: false)
        legacy.model.select(.small)
        #expect(legacy.model.choice == .apple && legacy.reports.savedKeys.isEmpty)
        #expect(legacy.model.choices == [.apple])
    }

    @Test func aTightModelAsksForConfirmationBeforeDownloading() throws {
        let database = try AppDatabase()
        let eight = HardwareProfile(
            chipName: "Apple M2", memoryBytes: 8 << 30, gpuBudgetBytes: 5 << 30, freeDiskBytes: 200 << 30)
        let provider = ModelProvider(
            storage: ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-am-\(UUID().uuidString)")),
            hardware: eight)
        let model = AssistantModel(
            provider: provider, snapshot: { AssistantSnapshot(tasks: TaskSet(), projects: [], goals: []) },
            batch: ChangeBatch(database: database), report: { _ in }, storedChoiceKey: nil, saveChoiceKey: { _ in },
            runsOnMacOS27OrLater: true)
        model.download(.balanced)
        #expect(model.confirmingDownload?.model == .balanced)
        #expect(provider.downloading == nil)
        model.cancelDownloadConfirmation()
        #expect(model.confirmingDownload == nil)
    }

    /// Opt-in (`TICKOFF_LIVE_MODEL_TESTS=1`): asks Apple's real on-device model, through the real provider and
    /// tools, to complete a task. Skipped silently where Apple Intelligence isn't ready.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TICKOFF_LIVE_MODEL_TESTS"] != nil))
    func appleIntelligenceProposesCompletingATaskThroughTheRealTools() async throws {
        let database = try AppDatabase()
        let tasks = TaskStore(database: database)
        let id = try tasks.insert(title: "Buy groceries", priority: .medium)
        let storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-am-\(UUID().uuidString)"))
        let provider = ModelProvider(storage: storage)
        guard case .ready = await provider.availability(of: .apple) else { return }
        let projects = ProjectStore(database: database)
        let model = AssistantModel(
            provider: provider,
            snapshot: {
                var set = TaskSet()
                set.replace((try? tasks.loadAll()) ?? [])
                return AssistantSnapshot(tasks: set, projects: (try? projects.loadAll()) ?? [], goals: [])
            },
            batch: ChangeBatch(database: database), report: { _ in }, storedChoiceKey: nil, saveChoiceKey: { _ in })
        model.send("I bought the groceries, please mark that task as done.")
        await waitUntilIdle(model, timeout: .seconds(90))
        #expect(model.status == .idle, "\(model.status)")
        #expect(
            model.proposals.map(\.change) == [.setStatus(taskID: id, .done)],
            "\(model.messages.map(\.text)) \(model.proposals.map(\.summary))")
        #expect(try tasks.loadAll().first?.status == .todo)
    }
}
