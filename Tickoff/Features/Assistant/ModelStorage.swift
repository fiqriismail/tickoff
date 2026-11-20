import Foundation

/// Where downloaded model weights live, and how much room they take. It knows the Hugging Face cache
/// layout (`models--<org>--<name>/blobs`) but nothing about MLX, so it is tested against a temporary folder.
struct ModelStorage: Sendable {
    let root: URL

    /// `~/Library/Application Support/Tickoff/Models/`, so weights can be listed and deleted by the app.
    static var `default`: ModelStorage {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ModelStorage(root: support.appendingPathComponent("Tickoff/Models", isDirectory: true))
    }

    /// The folder of one model, or nil for Apple's model.
    func directory(for model: ModelChoice) -> URL? {
        guard let id = model.repositoryID else { return nil }
        return root.appendingPathComponent("models--" + id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// Bytes the model's files occupy; 0 when nothing is downloaded. The snapshot folder only holds links
    /// to the blobs, so counting blobs avoids counting twice.
    func bytesOnDisk(_ model: ModelChoice) -> Int {
        guard let blobs = directory(for: model)?.appendingPathComponent("blobs") else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(at: blobs, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Whether a complete download is present: at least 90% of the expected size (a partial or failed
    /// download leaves less, and the provider's own check decides whether the weights are usable).
    func isDownloaded(_ model: ModelChoice) -> Bool {
        model.isDownloadable && bytesOnDisk(model) * 10 >= model.downloadBytes * 9
    }

    /// Frees the model's space. Deleting something that isn't there is not an error.
    func delete(_ model: ModelChoice) throws {
        guard let directory = directory(for: model), FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
