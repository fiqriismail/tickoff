import Foundation

/// Whether a Mac should be offered a model, decided from its `HardwareProfile` before any download
/// or load. Pure, so it is tested with fake Macs.
enum Eligibility: Equatable, Sendable {
    case recommended
    /// Allowed, but warn and confirm first.
    case tight(String)
    /// Not offered; there is no override.
    case blocked(String)

    /// Share of the GPU budget above which a model is refused / warned about.
    static let blockedShare = 0.70
    static let tightShare = 0.50
    /// Headroom kept free on top of the download itself.
    static let diskHeadroomBytes = 2 * 1_073_741_824

    static func of(_ model: ModelChoice, on mac: HardwareProfile) -> Eligibility {
        guard mac.supportsRequiredGPUFamily else {
            return .blocked("This Mac’s graphics chip is too old for on-device models.")
        }
        let peak = Double(model.peakMemoryBytes)
        let budget = Double(mac.gpuBudgetBytes)
        if peak > budget * blockedShare {
            return .blocked(
                "Needs about \(gigabytes(model.peakMemoryBytes)) of graphics memory; this Mac offers \(gigabytes(mac.gpuBudgetBytes)).")
        }
        let needed = model.downloadBytes + diskHeadroomBytes
        if mac.freeDiskBytes < needed {
            return .blocked("Needs \(gigabytes(needed)) of free disk space; \(gigabytes(mac.freeDiskBytes)) is available.")
        }
        if peak > budget * tightShare {
            return .tight("Uses most of this Mac’s graphics memory, so other apps may slow down.")
        }
        if mac.chip.isSlowBase && model != .small {
            return .tight("Works, but replies will be slow on this chip.")
        }
        return .recommended
    }

    private static func gigabytes(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
