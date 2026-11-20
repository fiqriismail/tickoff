import Foundation

/// The models the assistant can run: Apple's built-in one plus the curated downloadable MLX models.
/// The raw values are the stored `assistant_model` keys and never change.
/// Sizes come from the #67 spike (Qwen3 1.7B, 4B and 8B, 4-bit) on an M5 Pro 24 GB, rounded up; no 8 GB or 16 GB Mac was available.
enum ModelChoice: String, CaseIterable, Sendable {
    case apple, small, balanced, large

    var label: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .small: "Small"
        case .balanced: "Balanced"
        case .large: "Large"
        }
    }

    /// The MLX models, which are downloaded on demand.
    static let downloadable: [ModelChoice] = [.small, .balanced, .large]

    var isDownloadable: Bool { self != .apple }

    /// The Hugging Face repository holding the weights; nil for Apple's model.
    var repositoryID: String? {
        switch self {
        case .apple: nil
        case .small: "mlx-community/Qwen3-1.7B-4bit"
        case .balanced: "mlx-community/Qwen3-4B-4bit"
        case .large: "mlx-community/Qwen3-8B-4bit"
        }
    }

    /// Bytes to download (weights and tokenizer); 0 for Apple's model.
    var downloadBytes: Int {
        switch self {
        case .apple: 0
        case .small: 980_000_000
        case .balanced: 2_280_000_000
        case .large: 4_620_000_000
        }
    }

    /// Peak GPU memory while answering: weights, KV cache at our context length and overhead.
    /// Apple's model runs outside our process, so it counts as 0.
    var peakMemoryBytes: Int {
        switch self {
        case .apple: 0
        case .small: 2_100_000_000
        case .balanced: 3_100_000_000
        case .large: 7_700_000_000
        }
    }

    /// What the picker offers: the MLX models need the macOS 27 runtime, so macOS 26 sees Apple's model only.
    static func available(onMacOS27OrLater: Bool) -> [ModelChoice] {
        onMacOS27OrLater ? allCases : [.apple]
    }

    /// The stored choice if it can still be used, otherwise Apple's model: a missing or unknown key, an
    /// MLX model on a Mac that is back on macOS 26, or one this hardware now blocks all fall back.
    static func resolved(storedKey: String?, onMacOS27OrLater: Bool, on mac: HardwareProfile) -> ModelChoice {
        guard let storedKey, let stored = ModelChoice(rawValue: storedKey),
            available(onMacOS27OrLater: onMacOS27OrLater).contains(stored)
        else { return .apple }
        if case .blocked = Eligibility.of(stored, on: mac) { return .apple }
        return stored
    }
}
