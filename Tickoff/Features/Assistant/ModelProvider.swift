import Foundation
import FoundationModels
import HuggingFace
import MLX
import MLXFoundationModels
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Observation
import Tokenizers

/// The ONLY file that imports MLX (two copies of MLX in one process break). It turns a `ModelChoice` into a
/// `LanguageModel` (Apple's, or an MLX one on macOS 27+), downloads, deletes and unloads weights under
/// `ModelStorage`, and coordinates wired memory. Everything it exposes is plain Swift types, so the rest
/// of the Assistant feature never sees MLX.
@MainActor @Observable
final class ModelProvider {
    /// How long a loaded model stays in memory after its last answer.
    static let defaultIdleDelay: Duration = .seconds(300)

    let storage: ModelStorage
    private(set) var downloading: ModelChoice?

    let hardware: HardwareProfile
    private let idleDelay: Duration
    private var downloadTask: _Concurrency.Task<Void, any Error>?
    private var idleTask: _Concurrency.Task<Void, Never>?
    /// Loaded MLX models, boxed as `Any`: `FoundationModels.LanguageModel` itself needs macOS 27.
    private var loaded: [ModelChoice: Any] = [:]
    /// Loaded weights are tracked as a `.reservation` ticket so admission control knows they are resident.
    private var reservations: [ModelChoice: WiredMemoryTicket] = [:]
    /// One policy for every ticket, so reservations and active work add up against the same budget.
    private let policy = MLX.WiredSumPolicy()

    init(storage: ModelStorage = .default, hardware: HardwareProfile? = nil, idleDelay: Duration = defaultIdleDelay) {
        self.storage = storage
        self.hardware = hardware ?? .current(modelsDirectory: storage.root)
        self.idleDelay = idleDelay
    }

    // MARK: Status

    func eligibility(of choice: ModelChoice) -> Eligibility {
        Eligibility.of(choice, on: hardware)
    }

    func availability(of choice: ModelChoice) async -> ModelAvailability {
        guard choice.isDownloadable else { return Self.appleAvailability(SystemLanguageModel.default.availability) }
        if case .blocked(let reason) = eligibility(of: choice) { return .unavailable(reason) }
        guard #available(macOS 27.0, *), let model = makeModel(choice) else {
            return .unavailable("On-device models need macOS 27 or later.")
        }
        switch await model.availability {
        case .available: return .ready
        case .downloading: return .downloading(downloadFraction(of: choice) ?? 0)
        case .unavailable(.deviceNotCapable): return .unavailable("This Mac’s graphics chip can’t run on-device models.")
        case .unavailable(.modelNotDownloaded): return .notDownloaded
        case .unavailable(.downloadFailed): return .unavailable("The last download didn’t finish. Try again.")
        case .unavailable: return .unavailable("This model isn’t available right now.")
        }
    }

    /// 0 to 1 while `choice` is downloading, otherwise nil.
    func downloadFraction(of choice: ModelChoice) -> Double? {
        guard #available(macOS 27.0, *), let id = choice.repositoryID else { return nil }
        return MLXDownloadProgress.shared.download(forModelID: id)?.fractionCompleted
    }

    // MARK: Download and delete

    /// Downloads `choice` into `storage`. Blocked models are refused, tight ones until `confirmTight`.
    func download(_ choice: ModelChoice, confirmTight: Bool = false) async throws {
        guard choice.isDownloadable else { return }
        try eligibility(of: choice).require(confirmed: confirmTight)
        guard downloading == nil else { throw ModelAccessError.unavailable("Another download is running.") }
        guard #available(macOS 27.0, *), let model = makeModel(choice) else {
            throw ModelAccessError.unavailable("On-device models need macOS 27 or later.")
        }
        downloading = choice
        defer {
            downloading = nil
            downloadTask = nil
        }
        // `preload` downloads and loads the weights; evict right after so a download doesn't pin memory.
        let task = _Concurrency.Task {
            try await model.preload()
            await model.evict()
        }
        downloadTask = task
        try await task.value
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Frees the model's memory and disk space.
    func delete(_ choice: ModelChoice) async throws {
        if downloading == choice { cancelDownload() }
        await unload(choice)
        try storage.delete(choice)
    }

    // MARK: Load and generate

    /// Makes `choice` ready and returns a session on it with the given tools and instructions. The hardware
    /// check runs again here (disk or memory may have changed since the download) and a failed load is
    /// thrown, never a crash. Apple's model uses the macOS 26 session initializer; MLX models need macOS 27.
    func session(
        for choice: ModelChoice, tools: [any FoundationModels.Tool], instructions: String, confirmTight: Bool = false
    ) async throws -> LanguageModelSession {
        guard choice.isDownloadable else {
            if case .unavailable(let reason) = Self.appleAvailability(SystemLanguageModel.default.availability) {
                throw ModelAccessError.unavailable(reason)
            }
            return LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
        }
        try eligibility(of: choice).require(confirmed: confirmTight)
        guard storage.isDownloaded(choice) else { throw ModelAccessError.notDownloaded }
        guard #available(macOS 27.0, *) else {
            throw ModelAccessError.unavailable("On-device models need macOS 27 or later.")
        }
        let model = try await loadedModel(choice)
        return LanguageModelSession(model: model, tools: tools, instructions: instructions)
    }

    @available(macOS 27.0, *)
    private func loadedModel(_ choice: ModelChoice) async throws -> MLXLanguageModel {
        if let model = loaded[choice] as? MLXLanguageModel { return model }
        guard let model = makeModel(choice) else { throw ModelAccessError.unavailable("This model isn’t available.") }
        do {
            try await model.preload()
        } catch {
            throw ModelAccessError.unavailable("The model couldn’t be loaded: \(error.localizedDescription)")
        }
        // One model in memory at a time.
        for other in loaded.keys where other != choice { await unload(other) }
        let ticket = policy.ticket(size: choice.downloadBytes, kind: .reservation)
        _ = await ticket.start()
        reservations[choice] = ticket
        loaded[choice] = model
        return model
    }

    /// Runs one answer with an `.active` wired-memory ticket for the KV cache and working memory, then
    /// starts the idle countdown. The wired limit is never set directly.
    func generate<T>(with choice: ModelChoice, _ body: () async throws -> T) async rethrows -> T {
        idleTask?.cancel()
        defer { scheduleIdleUnload() }
        guard choice.isDownloadable else { return try await body() }
        let working = max(choice.peakMemoryBytes - choice.downloadBytes, 256_000_000)
        // The same pairing as `WiredMemoryTicket.withWiredLimit`, written out so `body` stays on the main actor.
        let ticket = policy.ticket(size: working, kind: .active)
        _ = await ticket.start()
        do {
            let result = try await body()
            _ = await ticket.end()
            return result
        } catch {
            _ = await ticket.end()
            throw error
        }
    }

    func unload(_ choice: ModelChoice) async {
        if let model = loaded.removeValue(forKey: choice), #available(macOS 27.0, *) {
            await (model as? MLXLanguageModel)?.evict()
        }
        if let ticket = reservations.removeValue(forKey: choice) { _ = await ticket.end() }
    }

    func unloadAll() async {
        for choice in Array(loaded.keys) { await unload(choice) }
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        guard !loaded.isEmpty else { return }
        idleTask = _Concurrency.Task { [idleDelay] in
            try? await _Concurrency.Task.sleep(for: idleDelay)
            guard !_Concurrency.Task.isCancelled else { return }
            await self.unloadAll()
        }
    }

    // MARK: MLX

    @available(macOS 27.0, *)
    private func makeModel(_ choice: ModelChoice) -> MLXLanguageModel? {
        let configuration: ModelConfiguration
        switch choice {
        case .apple: return nil
        case .small: configuration = LLMRegistry.qwen3_1_7b_4bit
        case .balanced: configuration = LLMRegistry.qwen3_4b_4bit
        case .large: configuration = LLMRegistry.qwen3_8b_4bit
        }
        let cache = HubCache(cacheDirectory: storage.root)
        return MLXLanguageModel(
            configuration: configuration,
            capabilities: [.toolCalling, .guidedGeneration],
            weightsLocation: { id in
                guard let repo = Repo.ID(rawValue: id) else { return cache.cacheDirectory }
                if let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
                    let snapshot = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit) {
                    return snapshot
                }
                return cache.repoDirectory(repo: repo, kind: .model)
            },
            load: { configuration, progress in
                try await loadModelContainer(
                    from: #hubDownloader(HubClient(cache: cache)), using: #huggingFaceTokenizerLoader(),
                    configuration: configuration, progress: progress)
            })
    }

    private static func appleAvailability(_ availability: SystemLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available: .ready
        case .unavailable(.deviceNotEligible): .unavailable("This Mac doesn’t support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled): .unavailable("Turn on Apple Intelligence in System Settings.")
        case .unavailable(.modelNotReady): .unavailable("Apple’s model is still getting ready. Try again in a few minutes.")
        case .unavailable: .unavailable("Apple’s model isn’t available right now.")
        }
    }
}
