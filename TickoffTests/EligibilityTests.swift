import Foundation
import Testing

@testable import Tickoff

struct EligibilityTests {
    private static let gb = 1_073_741_824

    /// A fake Mac; the GPU budget defaults to two thirds of memory, like Apple Silicon.
    private func mac(
        _ chip: String = "Apple M3 Pro", memoryGB: Int, gpuFamilyOK: Bool = true, freeDiskGB: Int = 200
    ) -> HardwareProfile {
        HardwareProfile(
            chipName: chip, memoryBytes: memoryGB * Self.gb, gpuBudgetBytes: memoryGB * Self.gb * 2 / 3,
            supportsRequiredGPUFamily: gpuFamilyOK, freeDiskBytes: freeDiskGB * Self.gb)
    }

    private func isTight(_ e: Eligibility) -> Bool { if case .tight = e { true } else { false } }
    private func isBlocked(_ e: Eligibility) -> Bool { if case .blocked = e { true } else { false } }

    @Test func an8GBMacGetsSmallBalancedTightAndLargeBlocked() {
        let m = mac(memoryGB: 8)
        #expect(Eligibility.of(.small, on: m) == .recommended)
        #expect(isTight(Eligibility.of(.balanced, on: m)))
        #expect(isBlocked(Eligibility.of(.large, on: m)))
    }

    @Test func a16GBMacGetsSmallAndBalancedRecommendedAndLargeTight() {
        let m = mac(memoryGB: 16)
        #expect(Eligibility.of(.small, on: m) == .recommended)
        #expect(Eligibility.of(.balanced, on: m) == .recommended)
        #expect(isTight(Eligibility.of(.large, on: m)))
    }

    @Test func a24GBMacGetsEveryModelRecommended() {
        let m = mac(memoryGB: 24)
        for model in ModelChoice.allCases { #expect(Eligibility.of(model, on: m) == .recommended) }
    }

    @Test func baseM1AndM2WarnAboutSpeedForBalancedAndLargeButProChipsDoNot() {
        for chip in ["Apple M1", "Apple M2"] {
            let m = mac(chip, memoryGB: 24)
            #expect(Eligibility.of(.small, on: m) == .recommended)
            #expect(isTight(Eligibility.of(.balanced, on: m)))
            #expect(isTight(Eligibility.of(.large, on: m)))
        }
        for chip in ["Apple M2 Pro", "Apple M1 Max", "Apple M3"] {
            #expect(Eligibility.of(.large, on: mac(chip, memoryGB: 24)) == .recommended)
        }
    }

    @Test func anUnsupportedGPUFamilyBlocksEveryModel() {
        let m = mac(memoryGB: 64, gpuFamilyOK: false)
        for model in ModelChoice.allCases { #expect(isBlocked(Eligibility.of(model, on: m))) }
    }

    @Test func lowDiskBlocksUntilTheDownloadPlusTwoGBFits() {
        // Small needs 0.91 GB + 2 GiB of headroom.
        #expect(isBlocked(Eligibility.of(.small, on: mac(memoryGB: 24, freeDiskGB: 2))))
        #expect(Eligibility.of(.small, on: mac(memoryGB: 24, freeDiskGB: 3)) == .recommended)
    }

    @Test func reasonsAreReadableSentences() {
        guard case .blocked(let memory) = Eligibility.of(.large, on: mac(memoryGB: 8)),
            case .tight(let slow) = Eligibility.of(.balanced, on: mac("Apple M1", memoryGB: 24)),
            case .blocked(let disk) = Eligibility.of(.small, on: mac(memoryGB: 24, freeDiskGB: 1)),
            case .blocked(let gpu) = Eligibility.of(.small, on: mac(memoryGB: 24, gpuFamilyOK: false))
        else { Issue.record("expected blocked, tight, blocked, blocked"); return }
        #expect(memory.contains("graphics memory") && memory.contains("GB"))
        #expect(slow.contains("slow"))
        #expect(disk.contains("free disk space"))
        #expect(gpu.contains("too old"))
    }
}

struct HardwareProfileTests {
    @Test func chipBrandStringsParseIntoGenerationAndVariant() {
        let cases: [(String, Int?, HardwareProfile.ChipVariant)] = [
            ("Apple M1", 1, .base), ("Apple M2 Pro", 2, .pro), ("Apple M3 Max", 3, .max),
            ("Apple M4 Ultra", 4, .ultra), ("Apple M5 Pro", 5, .pro), ("Intel(R) Core(TM) i7", nil, .base),
        ]
        for (name, generation, variant) in cases {
            let chip = HardwareProfile.Chip(brandString: name)
            #expect(chip.generation == generation && chip.variant == variant)
        }
    }

    @Test func onlyBaseM1AndM2CountAsSlow() {
        #expect(HardwareProfile.Chip(brandString: "Apple M2").isSlowBase)
        #expect(!HardwareProfile.Chip(brandString: "Apple M3").isSlowBase)
        #expect(!HardwareProfile.Chip(brandString: "Apple M1 Pro").isSlowBase)
        #expect(!HardwareProfile.Chip(brandString: "Mystery").isSlowBase)
    }

    @Test func theCurrentMacReportsPlausibleFacts() {
        let mac = HardwareProfile.current(modelsDirectory: URL(filePath: "/nonexistent/Tickoff/Models"))
        #expect(mac.memoryBytes > 0 && mac.freeDiskBytes > 0 && mac.gpuBudgetBytes > 0)
        #expect(!mac.chipName.isEmpty)
    }
}
