import Foundation

/// The curated downloadable models. The sizes drive `Eligibility`; the stored key never changes.
/// Sizes come from the #67 spike (Qwen3 1.7B, 4B and 8B, 4-bit) on an M5 Pro 24 GB, rounded up; no 8 GB or 16 GB Mac was available.
enum ModelChoice: String, CaseIterable, Sendable {
    case small, balanced, large

    var label: String {
        switch self {
        case .small: "Small"
        case .balanced: "Balanced"
        case .large: "Large"
        }
    }

    /// Bytes to download (weights and tokenizer).
    var downloadBytes: Int {
        switch self {
        case .small: 980_000_000
        case .balanced: 2_280_000_000
        case .large: 4_620_000_000
        }
    }

    /// Peak GPU memory while answering: weights, KV cache at our context length and overhead.
    var peakMemoryBytes: Int {
        switch self {
        case .small: 2_100_000_000
        case .balanced: 3_100_000_000
        case .large: 7_700_000_000
        }
    }
}
