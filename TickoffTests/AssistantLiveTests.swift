import Foundation
import FoundationModels
import Testing

@testable import Tickoff

/// Opt-in (`TICKOFF_LIVE_MODEL_TESTS=1`) checks that drive Apple's real model into a full context and through a
/// streamed answer, which the scripted model can't reproduce.
@MainActor
struct AssistantLiveTests {
    private final class Counter { var sessions = 0 }

    private func makeModel(factory: AssistantModel.SessionFactory? = nil, hardware: HardwareProfile? = nil) throws -> (AssistantModel, TaskStore) {
        let database = try AppDatabase()
        let tasks = TaskStore(database: database)
        let projects = ProjectStore(database: database)
        try tasks.insert(title: "Buy groceries", priority: .medium)
        try tasks.insert(title: "Call dentist", priority: .medium)
        let storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-pv-\(UUID().uuidString)"))
        let provider = hardware.map { ModelProvider(storage: storage, hardware: $0) } ?? ModelProvider(storage: storage)
        let model = AssistantModel(
            provider: provider,
            snapshot: {
                var set = TaskSet()
                set.replace((try? tasks.loadAll()) ?? [])
                return AssistantSnapshot(tasks: set, projects: (try? projects.loadAll()) ?? [], goals: [])
            },
            batch: ChangeBatch(database: database), report: { _ in }, storedChoiceKey: nil, saveChoiceKey: { _ in },
            runsOnMacOS27OrLater: true, makeSession: factory)
        return (model, tasks)
    }

    /// A prompt far beyond Apple's context window must raise the real overflow error, and the model must
    /// recognise it, start a second session once, then report the failure instead of hanging.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TICKOFF_LIVE_MODEL_TESTS"] != nil))
    func aFullContextRestartsTheSessionOnceThenFails() async throws {
        let counter = Counter()
        let storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-pv-\(UUID().uuidString)"))
        let provider = ModelProvider(storage: storage)
        guard case .ready = await provider.availability(of: .apple) else { return }
        let (model, _) = try makeModel(factory: { choice, tools, instructions in
            counter.sessions += 1
            return try await provider.session(for: choice, tools: tools, instructions: instructions)
        })
        model.send(String(repeating: "tick off the groceries and the dentist call. ", count: 20_000))
        for _ in 0..<1500 where model.isBusy { try await _Concurrency.Task.sleep(for: .milliseconds(100)) }
        #expect(counter.sessions == 2, "sessions \(counter.sessions), status \(model.status)")
        guard case .failed = model.status else { Issue.record("status \(model.status)"); return }
    }

    /// The reply grows in several steps, not in one piece at the end.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TICKOFF_LIVE_MODEL_TESTS"] != nil))
    func aLiveAnswerStreamsInSeveralSteps() async throws {
        let storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-pv-\(UUID().uuidString)"))
        let provider = ModelProvider(storage: storage)
        guard case .ready = await provider.availability(of: .apple) else { return }
        let (model, _) = try makeModel()
        model.send("Explain in three sentences what you can help me with.")
        var lengths: [Int] = []
        for _ in 0..<1500 where model.isBusy {
            if let last = model.messages.last, last.role == .assistant { lengths.append(last.text.count) }
            try await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
        let distinct = Set(lengths.filter { $0 > 0 })
        #expect(model.status == .idle, "\(model.status)")
        #expect(distinct.count > 2, "steps \(distinct.sorted())")
    }
}
