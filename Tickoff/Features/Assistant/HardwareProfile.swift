import Foundation
import Metal

/// What this Mac can run, read once from Metal, `sysctl` and the file system. It imports no MLX, so
/// the model eligibility check works on macOS 26 and in tests, which build profiles by hand.
struct HardwareProfile: Equatable, Sendable {
    /// The Apple Silicon line a chip belongs to; only `base` matters for the speed warning.
    enum ChipVariant: String, Sendable { case base, pro, max, ultra }

    struct Chip: Equatable, Sendable {
        /// 1 for M1 and so on; nil when the brand string isn't an "Apple M<n>" chip.
        var generation: Int?
        var variant: ChipVariant

        /// Parses `machdep.cpu.brand_string`, e.g. "Apple M2 Pro". Unknown strings read as nil/base.
        init(brandString: String) {
            let words = brandString.split(separator: " ").map(String.init)
            let model = words.first { $0.count >= 2 && $0.hasPrefix("M") && Int($0.dropFirst()) != nil }
            generation = model.flatMap { Int($0.dropFirst()) }
            let suffix = words.last?.lowercased() ?? ""
            variant = ChipVariant(rawValue: suffix) ?? .base
        }

        /// Base M1/M2 chips have the least memory bandwidth, so larger models reply slowly.
        var isSlowBase: Bool { variant == .base && (generation ?? 0) <= 2 && generation != nil }
    }

    var chip: Chip
    var chipName: String
    var memoryBytes: Int
    /// `MTLDevice.recommendedMaxWorkingSetSize`, the most GPU memory the system advises using.
    var gpuBudgetBytes: Int
    /// False when the GPU is older than the Apple family MLX needs.
    var supportsRequiredGPUFamily: Bool
    /// Space available for the downloaded weights.
    var freeDiskBytes: Int

    init(
        chipName: String, memoryBytes: Int, gpuBudgetBytes: Int, supportsRequiredGPUFamily: Bool = true,
        freeDiskBytes: Int
    ) {
        self.chipName = chipName
        chip = Chip(brandString: chipName)
        self.memoryBytes = memoryBytes
        self.gpuBudgetBytes = gpuBudgetBytes
        self.supportsRequiredGPUFamily = supportsRequiredGPUFamily
        self.freeDiskBytes = freeDiskBytes
    }

    /// Reads this Mac. `modelsDirectory` may not exist yet; its nearest existing parent is measured.
    static func current(modelsDirectory: URL) -> HardwareProfile {
        let device = MTLCreateSystemDefaultDevice()
        return HardwareProfile(
            chipName: sysctlString("machdep.cpu.brand_string") ?? "Unknown chip",
            memoryBytes: Int(clamping: ProcessInfo.processInfo.physicalMemory),
            gpuBudgetBytes: device.map { Int(clamping: $0.recommendedMaxWorkingSetSize) } ?? 0,
            supportsRequiredGPUFamily: device?.supportsFamily(.apple7) ?? false,
            freeDiskBytes: freeDiskBytes(near: modelsDirectory))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func freeDiskBytes(near directory: URL) -> Int {
        var url = directory
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        return capacity.map { Int(clamping: $0) } ?? 0
    }
}
