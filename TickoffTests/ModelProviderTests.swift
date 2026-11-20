import Foundation
import FoundationModels
import Testing

@testable import Tickoff

@MainActor
struct ModelProviderTests {
    private let gb = 1_073_741_824

    private func mac(memoryGB: Int, freeDiskGB: Int = 200) -> HardwareProfile {
        HardwareProfile(
            chipName: "Apple M3 Pro", memoryBytes: memoryGB * gb, gpuBudgetBytes: memoryGB * gb * 2 / 3,
            freeDiskBytes: freeDiskGB * gb)
    }

    private func makeProvider(memoryGB: Int, freeDiskGB: Int = 200) -> (ModelProvider, ModelStorage) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-provider-\(UUID().uuidString)")
        let storage = ModelStorage(root: root)
        return (ModelProvider(storage: storage, hardware: mac(memoryGB: memoryGB, freeDiskGB: freeDiskGB)), storage)
    }

    @Test func eligibilityRequireRefusesBlockedAndUnconfirmedTightButAllowsTheRest() throws {
        #expect(throws: ModelAccessError.blocked("no")) { try Eligibility.blocked("no").require(confirmed: true) }
        #expect(throws: ModelAccessError.needsConfirmation("slow")) { try Eligibility.tight("slow").require(confirmed: false) }
        try Eligibility.tight("slow").require(confirmed: true)
        try Eligibility.recommended.require(confirmed: false)
    }

    @Test func aBlockedModelCannotBeDownloadedOrLoaded() async throws {
        let (provider, storage) = makeProvider(memoryGB: 8)
        let blocked = try #require(
            { if case .blocked(let r) = provider.eligibility(of: .large) { r } else { nil } }())
        await #expect(throws: ModelAccessError.blocked(blocked)) { try await provider.download(.large, confirmTight: true) }
        await #expect(throws: ModelAccessError.blocked(blocked)) {
            _ = try await provider.session(for: .large, tools: [], instructions: "", confirmTight: true)
        }
        #expect(provider.downloading == nil && storage.bytesOnDisk(.large) == 0)
        #expect(await provider.availability(of: .large) == .unavailable(blocked))
    }

    @Test func aTightModelNeedsConfirmationBeforeItDownloads() async throws {
        let (provider, _) = makeProvider(memoryGB: 8)
        let reason = try #require(
            { if case .tight(let r) = provider.eligibility(of: .balanced) { r } else { nil } }())
        await #expect(throws: ModelAccessError.needsConfirmation(reason)) { try await provider.download(.balanced) }
        await #expect(throws: ModelAccessError.needsConfirmation(reason)) {
            _ = try await provider.session(for: .balanced, tools: [], instructions: "")
        }
    }

    @Test func loadingAModelThatIsNotDownloadedSaysSo() async throws {
        let (provider, _) = makeProvider(memoryGB: 24)
        await #expect(throws: ModelAccessError.notDownloaded) {
            _ = try await provider.session(for: .small, tools: [], instructions: "")
        }
        #expect(await provider.availability(of: .small) == .notDownloaded)
    }

    @Test func deletingFreesTheDiskSpace() async throws {
        let (provider, storage) = makeProvider(memoryGB: 24)
        let blobs = try #require(storage.directory(for: .small)).appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try Data(count: ModelChoice.small.downloadBytes).write(to: blobs.appendingPathComponent("weights"))
        #expect(storage.isDownloaded(.small))
        try await provider.delete(.small)
        #expect(storage.bytesOnDisk(.small) == 0 && !storage.isDownloaded(.small))
    }

    @Test func appleNeverDownloadsAndReportsItsOwnAvailability() async throws {
        let (provider, storage) = makeProvider(memoryGB: 8, freeDiskGB: 0)
        try await provider.download(.apple)
        #expect(provider.downloading == nil && storage.bytesOnDisk(.apple) == 0)
        let availability = await provider.availability(of: .apple)
        if case .downloading = availability { Issue.record("Apple's model is never downloaded by us") }
    }

    /// Opt-in because it downloads about 1 GB: `TICKOFF_LIVE_MODEL_TESTS=1`. Proves the full path on this Mac:
    /// download into our own folder, load, answer, unload and delete.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TICKOFF_LIVE_MODEL_TESTS"] != nil))
    func theSmallModelDownloadsLoadsAnswersAndDeletesForReal() async throws {
        guard #available(macOS 27.0, *) else { return }
        let (provider, storage) = makeProvider(memoryGB: 24)
        #expect(await provider.availability(of: .small) == .notDownloaded)
        try await provider.download(.small)
        #expect(storage.isDownloaded(.small))
        #expect(await provider.availability(of: .small) == .ready)
        let session = try await provider.session(for: .small, tools: [], instructions: "Answer in one short sentence.")
        let reply = try await provider.generate(with: .small) { try await session.respond(to: "Say hello.") }
        #expect(!reply.content.isEmpty)
        await provider.unloadAll()
        try await provider.delete(.small)
        #expect(storage.bytesOnDisk(.small) == 0)
    }
}
