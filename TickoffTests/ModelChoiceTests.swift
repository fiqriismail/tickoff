import Foundation
import Testing

@testable import Tickoff

struct ModelChoiceTests {
    private let gb = 1_073_741_824

    private func mac(memoryGB: Int, freeDiskGB: Int = 200) -> HardwareProfile {
        HardwareProfile(
            chipName: "Apple M3 Pro", memoryBytes: memoryGB * gb, gpuBudgetBytes: memoryGB * gb * 2 / 3,
            freeDiskBytes: freeDiskGB * gb)
    }

    @Test func storedKeysNeverChange() {
        #expect(ModelChoice.allCases.map(\.rawValue) == ["apple", "small", "balanced", "large"])
    }

    @Test func macOS26OffersOnlyAppleAndMacOS27AddsTheDownloadableModels() {
        #expect(ModelChoice.available(onMacOS27OrLater: false) == [.apple])
        #expect(ModelChoice.available(onMacOS27OrLater: true) == [.apple, .small, .balanced, .large])
    }

    @Test func appleNeedsNoDownloadAndNoMemoryAndIsAlwaysRecommended() {
        #expect(!ModelChoice.apple.isDownloadable && ModelChoice.apple.repositoryID == nil)
        #expect(ModelChoice.apple.downloadBytes == 0 && ModelChoice.apple.peakMemoryBytes == 0)
        #expect(Eligibility.of(.apple, on: mac(memoryGB: 8, freeDiskGB: 0)) == .recommended)
    }

    @Test func everyDownloadableModelHasARepositoryAndSizes() {
        for model in ModelChoice.downloadable {
            #expect(model.isDownloadable && model.repositoryID?.hasPrefix("mlx-community/") == true)
            #expect(model.downloadBytes > 0 && model.peakMemoryBytes > model.downloadBytes / 2)
        }
    }

    @Test func aMissingOrUnknownStoredKeyFallsBackToApple() {
        for key in [nil, "", "gpt", "Balanced"] as [String?] {
            #expect(ModelChoice.resolved(storedKey: key, onMacOS27OrLater: true, on: mac(memoryGB: 24)) == .apple)
        }
    }

    @Test func aStoredChoiceIsKeptWhenItIsAvailableAndAllowed() {
        #expect(ModelChoice.resolved(storedKey: "balanced", onMacOS27OrLater: true, on: mac(memoryGB: 16)) == .balanced)
        #expect(ModelChoice.resolved(storedKey: "apple", onMacOS27OrLater: false, on: mac(memoryGB: 8)) == .apple)
    }

    @Test func aStoredMLXChoiceFallsBackToAppleOnMacOS26() {
        #expect(ModelChoice.resolved(storedKey: "small", onMacOS27OrLater: false, on: mac(memoryGB: 64)) == .apple)
    }

    @Test func aStoredChoiceThatHardwareNowBlocksFallsBackToApple() {
        // Large needs about 7.7 GB of GPU memory; an 8 GB Mac offers about 5.7 GB.
        #expect(ModelChoice.resolved(storedKey: "large", onMacOS27OrLater: true, on: mac(memoryGB: 8)) == .apple)
        // Out of disk space blocks too, even for the small model.
        #expect(ModelChoice.resolved(storedKey: "small", onMacOS27OrLater: true, on: mac(memoryGB: 24, freeDiskGB: 1)) == .apple)
    }

    @Test func aTightChoiceIsKeptBecauseOnlyBlockedOnesFallBack() {
        #expect(ModelChoice.resolved(storedKey: "balanced", onMacOS27OrLater: true, on: mac(memoryGB: 8)) == .balanced)
    }
}

struct ModelStorageTests {
    private func makeStorage() throws -> ModelStorage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tickoff-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ModelStorage(root: root)
    }

    private func writeBlob(_ model: ModelChoice, in storage: ModelStorage, bytes: Int) throws {
        let blobs = try #require(storage.directory(for: model)).appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: blobs.appendingPathComponent(UUID().uuidString))
    }

    @Test func eachModelGetsItsOwnHuggingFaceStyleFolderAndAppleGetsNone() throws {
        let storage = try makeStorage()
        #expect(storage.directory(for: .balanced)?.lastPathComponent == "models--mlx-community--Qwen3-4B-4bit")
        #expect(storage.directory(for: .apple) == nil)
    }

    @Test func nothingDownloadedMeansZeroBytesAndNotDownloaded() throws {
        let storage = try makeStorage()
        for model in ModelChoice.allCases {
            #expect(storage.bytesOnDisk(model) == 0 && !storage.isDownloaded(model))
        }
    }

    @Test func bytesOnDiskSumsTheBlobsAndAPartialDownloadDoesNotCountAsDownloaded() throws {
        let storage = try makeStorage()
        try writeBlob(.small, in: storage, bytes: 1_000)
        try writeBlob(.small, in: storage, bytes: 2_000)
        #expect(storage.bytesOnDisk(.small) == 3_000)
        #expect(!storage.isDownloaded(.small))
        try writeBlob(.small, in: storage, bytes: ModelChoice.small.downloadBytes)
        #expect(storage.isDownloaded(.small))
    }

    @Test func deletingFreesTheSpaceAndLeavesOtherModelsAlone() throws {
        let storage = try makeStorage()
        try writeBlob(.small, in: storage, bytes: 5_000)
        try writeBlob(.balanced, in: storage, bytes: 7_000)
        try storage.delete(.small)
        #expect(storage.bytesOnDisk(.small) == 0)
        #expect(storage.bytesOnDisk(.balanced) == 7_000)
        try storage.delete(.small)
        try storage.delete(.apple)
    }
}
