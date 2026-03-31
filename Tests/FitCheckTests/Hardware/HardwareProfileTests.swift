import Foundation
import Testing
@testable import FitCheck

// MARK: - Test fixtures

struct MockHardwareProfiler: HardwareProfiler {
    let result: Result<HardwareProfile, FitCheckError>

    func profile() throws -> HardwareProfile {
        try result.get()
    }
}

extension HardwareProfile {
    static func fixture(
        chip: Chip = .appleSilicon(.m2),
        totalMemoryBytes: UInt64 = 16 * 1_073_741_824,
        gpuCoreCount: Int = 10,
        cpuCoreCount: Int = 8,
        cpuPerformanceCores: Int = 4,
        cpuEfficiencyCores: Int = 4,
        neuralEngineCoreCount: Int = 16,
        metalSupport: MetalSupport = MetalSupport(
            isSupported: true,
            maxBufferLengthBytes: 16 * 1_073_741_824,
            recommendedMaxWorkingSetSizeBytes: 14 * 1_073_741_824
        )
    ) -> HardwareProfile {
        HardwareProfile(
            chip: chip,
            totalMemoryBytes: totalMemoryBytes,
            gpuCoreCount: gpuCoreCount,
            cpuCoreCount: cpuCoreCount,
            cpuPerformanceCores: cpuPerformanceCores,
            cpuEfficiencyCores: cpuEfficiencyCores,
            neuralEngineCoreCount: neuralEngineCoreCount,
            osVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
            metalSupport: metalSupport
        )
    }
}

// MARK: - HardwareProfile tests

@Suite("HardwareProfile")
struct HardwareProfileTests {
    @Test("Available memory uses utilization formula: min(0.85*total, total-2GB)")
    func availableMemory16GB() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 16 * 1_073_741_824)
        let available = profile.availableMemoryForInferenceBytes
        let expectedGB = min(0.85 * 16, 16 - 2)
        let expected = UInt64(expectedGB * 1_073_741_824)
        #expect(available == expected)
    }

    @Test("Available memory on 8 GB Mac leaves ~6 GB for inference")
    func availableMemory8GB() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 8 * 1_073_741_824)
        let availableGB = Double(profile.availableMemoryForInferenceBytes) / 1_073_741_824
        #expect(availableGB >= 5.5)
        #expect(availableGB <= 7.0)
    }

    @Test("Available memory floors at 1 GB")
    func availableMemoryFloor() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 2 * 1_073_741_824)
        #expect(profile.availableMemoryForInferenceBytes == 1_073_741_824)
    }

    @Test("hasNeuralEngine returns true for Apple Silicon")
    func neuralEngineDetection() {
        let profile = HardwareProfile.fixture(chip: .appleSilicon(.m3Pro))
        #expect(profile.hasNeuralEngine)
    }

    @Test("Total memory converts to GB correctly")
    func memoryConversion() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 36 * 1_073_741_824)
        #expect(profile.totalMemoryGB == 36.0)
    }

    @Test("Profile is Codable round-trip")
    func codableRoundTrip() throws {
        let profile = HardwareProfile.fixture()
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        let decoded = try JSONDecoder().decode(HardwareProfile.self, from: data)
        #expect(decoded == profile)
    }

    @Test("SystemHardwareProfiler returns a valid profile on this machine")
    func liveProfile() throws {
        let profiler = SystemHardwareProfiler()
        let profile = try profiler.profile()
        #expect(profile.totalMemoryBytes > 0)
        #expect(profile.cpuCoreCount > 0)
        #expect(profile.metalSupport.isSupported)
    }
}

// MARK: - Chip tests

@Suite("Chip")
struct ChipTests {
    @Test("ChipTier ordering: base < pro < max < ultra")
    func tierOrdering() {
        #expect(ChipTier.base < .pro)
        #expect(ChipTier.pro < .max)
        #expect(ChipTier.max < .ultra)
    }

    @Test("ChipFamily ordering: m1 < m2 < m3 < m4")
    func familyOrdering() {
        #expect(ChipFamily.m1 < .m2)
        #expect(ChipFamily.m2 < .m3)
        #expect(ChipFamily.m3 < .m4)
    }

    @Test("AppleSiliconVariant family assignment")
    func familyAssignment() {
        #expect(AppleSiliconVariant.m3Pro.family == .m3)
        #expect(AppleSiliconVariant.m4Ultra.family == .m4)
        #expect(AppleSiliconVariant.m1.family == .m1)
    }

    @Test("AppleSiliconVariant tier assignment")
    func tierAssignment() {
        #expect(AppleSiliconVariant.m2.tier == .base)
        #expect(AppleSiliconVariant.m3Pro.tier == .pro)
        #expect(AppleSiliconVariant.m4Max.tier == .max)
        #expect(AppleSiliconVariant.m1Ultra.tier == .ultra)
    }
}
