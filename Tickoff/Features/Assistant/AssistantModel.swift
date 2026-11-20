import Foundation
import FoundationModels
import Observation

/// The assistant's conversation and model state: one `LanguageModelSession`, an in-memory transcript,
/// streaming, the pending proposals, and the model picker's choices. It never writes tasks itself:
/// approved proposals go through `ChangeBatch` and the shell is told with an `Outcome`.
@MainActor @Observable
final class AssistantModel {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    enum Status: Equatable {
        case idle
        /// Loading the model or building the session.
        case preparing
        case responding
        case failed(String)
    }

    /// Builds a session for a choice; `ModelProvider.session` in the app, a scripted model in tests.
    typealias SessionFactory = (ModelChoice, [any FoundationModels.Tool], String) async throws -> LanguageModelSession

    private(set) var messages: [Message] = []
    private(set) var status: Status = .idle
    private(set) var proposals: [Proposal] = []
    private(set) var choice: ModelChoice
    private(set) var availability: [ModelChoice: ModelAvailability] = [:]
    /// A message about the model picker (download refused, delete failed); cleared by the next action.
    private(set) var notice: String?
    /// A tight model waiting for the user's go-ahead to download.
    private(set) var confirmingDownload: (model: ModelChoice, reason: String)?

    let provider: ModelProvider
    let choices: [ModelChoice]

    private let workspace: AssistantWorkspace
    private let snapshot: () -> AssistantSnapshot
    private let batch: ChangeBatch
    private let report: (Outcome) -> Void
    private let saveChoiceKey: (String) -> Void
    private let makeSession: SessionFactory
    private var session: LanguageModelSession?
    private var turn: _Concurrency.Task<Void, Never>?
    /// What the last conversation was about, carried into the next session after the context fills up.
    private var carriedSummary: String?

    var isBusy: Bool { status == .preparing || status == .responding }

    init(
        provider: ModelProvider, snapshot: @escaping () -> AssistantSnapshot, batch: ChangeBatch,
        report: @escaping (Outcome) -> Void, storedChoiceKey: String?, saveChoiceKey: @escaping (String) -> Void,
        runsOnMacOS27OrLater: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)),
        makeSession: SessionFactory? = nil
    ) {
        self.provider = provider
        self.snapshot = snapshot
        self.batch = batch
        self.report = report
        self.saveChoiceKey = saveChoiceKey
        workspace = AssistantWorkspace(snapshot: snapshot())
        choices = ModelChoice.available(onMacOS27OrLater: runsOnMacOS27OrLater)
        choice = ModelChoice.resolved(
            storedKey: storedChoiceKey, onMacOS27OrLater: runsOnMacOS27OrLater, on: provider.hardware)
        self.makeSession = makeSession ?? { choice, tools, instructions in
            try await provider.session(for: choice, tools: tools, instructions: instructions)
        }
    }

    // MARK: Conversation

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        notice = nil
        messages.append(Message(role: .user, text: prompt))
        let reply = Message(role: .assistant, text: "")
        messages.append(reply)
        status = .preparing
        turn = _Concurrency.Task { await run(prompt, replyID: reply.id) }
    }

    /// Cancels the answer in progress; whatever streamed so far stays in the transcript.
    func stop() {
        turn?.cancel()
    }

    /// Forgets the conversation and the pending proposals.
    func newConversation() {
        turn?.cancel()
        session = nil
        carriedSummary = nil
        messages = []
        workspace.discardAllProposals()
        proposals = []
        status = .idle
    }

    private func run(_ prompt: String, replyID: UUID, retried: Bool = false) async {
        workspace.update(snapshot())
        do {
            let session = try await currentSession()
            status = .responding
            try await provider.generate(with: choice) {
                for try await partial in session.streamResponse(to: prompt) {
                    setText(partial.content, of: replyID)
                }
            }
            // A cancelled stream may simply end instead of throwing.
            if _Concurrency.Task.isCancelled {
                finishStopped(replyID)
            } else {
                if text(of: replyID).isEmpty {
                    setText(workspace.proposals.isEmpty ? "I don’t have an answer for that." : "I’ve prepared changes for you to review.", of: replyID)
                }
                status = .idle
            }
        } catch is CancellationError {
            finishStopped(replyID)
        } catch {
            if _Concurrency.Task.isCancelled {
                finishStopped(replyID)
            } else if !retried, Self.isContextFull(error) {
                carriedSummary = summaryOfConversation(excluding: replyID)
                session = nil
                setText("", of: replyID)
                await run(prompt, replyID: replyID, retried: true)
                return
            } else {
                setText("", of: replyID)
                messages.removeAll { $0.id == replyID && $0.text.isEmpty }
                status = .failed(error.localizedDescription)
            }
        }
        proposals = workspace.proposals
    }

    private func currentSession() async throws -> LanguageModelSession {
        if let session { return session }
        var instructions = AssistantWorkspace.instructions(for: workspace.snapshot)
        if let carriedSummary {
            instructions += "\nThe earlier conversation was long, so it was cleared. Where it left off:\n\(carriedSummary)"
        }
        let created = try await makeSession(choice, AssistantTools.all(workspace), instructions)
        session = created
        return created
    }

    private func finishStopped(_ id: UUID) {
        if text(of: id).isEmpty { messages.removeAll { $0.id == id } } else { setText(text(of: id) + " …", of: id) }
        status = .idle
    }

    private func text(of id: UUID) -> String { messages.first { $0.id == id }?.text ?? "" }

    private func setText(_ text: String, of id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].text = text }
    }

    /// The last few turns, shortened, for the next session. No model call: it must work when the context is full.
    private func summaryOfConversation(excluding id: UUID) -> String {
        messages.filter { $0.id != id && !$0.text.isEmpty }.suffix(6).map {
            "\($0.role == .user ? "User" : "Assistant"): \(String($0.text.prefix(200)))"
        }.joined(separator: "\n")
    }

    private static func isContextFull(_ error: any Error) -> Bool {
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error { return true }
        if #available(macOS 27.0, *), case LanguageModelError.contextSizeExceeded = error { return true }
        return false
    }

    // MARK: Proposals

    func apply(_ proposal: Proposal) { apply([proposal]) }
    func applyAll() { apply(proposals) }

    /// Applies the proposals in one transaction. The database re-checks every id and project, so a
    /// proposal made before the data changed fails cleanly instead of writing something stale.
    private func apply(_ chosen: [Proposal]) {
        guard !chosen.isEmpty else { return }
        let outcome = batch.apply(chosen.map(\.change))
        if outcome == .changed { chosen.forEach { workspace.discardProposal(id: $0.id) } }
        report(outcome)
        workspace.update(snapshot())
        proposals = workspace.proposals
    }

    func discard(_ proposal: Proposal) {
        workspace.discardProposal(id: proposal.id)
        proposals = workspace.proposals
    }

    func discardAll() {
        workspace.discardAllProposals()
        proposals = []
    }

    // MARK: Models

    func refreshAvailability() async {
        for model in choices { availability[model] = await provider.availability(of: model) }
    }

    func select(_ model: ModelChoice) {
        guard choices.contains(model), model != choice else { return }
        turn?.cancel()
        choice = model
        session = nil
        status = .idle
        saveChoiceKey(model.rawValue)
    }

    /// Starts a download, or asks first when the hardware check says the model is a tight fit.
    func download(_ model: ModelChoice) {
        notice = nil
        if case .tight(let reason) = provider.eligibility(of: model) {
            confirmingDownload = (model, reason)
        } else {
            startDownload(model, confirmed: false)
        }
    }

    func confirmDownload() {
        guard let pending = confirmingDownload else { return }
        confirmingDownload = nil
        startDownload(pending.model, confirmed: true)
    }

    func cancelDownloadConfirmation() { confirmingDownload = nil }

    func cancelDownload() { provider.cancelDownload() }

    private func startDownload(_ model: ModelChoice, confirmed: Bool) {
        _Concurrency.Task {
            do {
                try await provider.download(model, confirmTight: confirmed)
            } catch is CancellationError {
            } catch {
                notice = error.localizedDescription
            }
            await refreshAvailability()
        }
    }

    func delete(_ model: ModelChoice) {
        _Concurrency.Task {
            do {
                try await provider.delete(model)
                if model == choice { select(.apple) }
            } catch {
                notice = error.localizedDescription
            }
            await refreshAvailability()
        }
    }
}
