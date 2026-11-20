import Foundation

/// What the picker says about a model right now, in plain terms. `ModelProvider` produces it from
/// Apple's availability, MLX's availability and the files on disk.
enum ModelAvailability: Equatable, Sendable {
    case ready
    /// A download is running; the fraction is 0 to 1.
    case downloading(Double)
    case notDownloaded
    /// The model can't be used, with a sentence the user can act on.
    case unavailable(String)
}
