import Foundation

/// The curated downloadable models. The sizes drive `Eligibility`; the stored key never changes.
/// Numbers marked provisional are estimates until the #67 spike measures them on 8 GB and 16 GB Macs.
enum ModelChoice: String, CaseIterable, Sendable {
    case small, balanced, large

    var label: String {
        switch self {
        case .small: "Small"
        case .balanced: "Balanced"
        case .large: "Large"
        }
    }

    /// Bytes to download (weights and tokenizer). Small is measured (Qwen3 1.7B 4-bit); the rest are provisional.
    var downloadBytes: Int {
        switch self {
        case .small: 910_000_000
        case .balanced: 2_300_000_000
        case .large: 4_500_000_000
        }
    }

    /// Peak GPU memory while answering: weights, KV cache at our context length and overhead.
    /// Small is measured (1.94 GB peak); the rest are provisional.
    var peakMemoryBytes: Int {
        switch self {
        case .small: 2_000_000_000
        case .balanced: 3_500_000_000
        case .large: 6_500_000_000
        }
    }
}
