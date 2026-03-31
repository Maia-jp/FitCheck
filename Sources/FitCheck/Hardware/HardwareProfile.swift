import Foundation

public struct HardwareProfile: Sendable, Equatable, Codable {
    public let chip: Chip
    public let totalMemoryBytes: UInt64
    public let gpuCoreCount: Int
    public let cpuCoreCount: Int
    public let cpuPerformanceCores: Int
    public let cpuEfficiencyCores: Int
    public let neuralEngineCoreCount: Int
    public let osVersion: OperatingSystemVersion
    public let metalSupport: MetalSupport

    public init(
        chip: Chip,
        totalMemoryBytes: UInt64,
        gpuCoreCount: Int,
        cpuCoreCount: Int,
        cpuPerformanceCores: Int,
        cpuEfficiencyCores: Int,
        neuralEngineCoreCount: Int,
        osVersion: OperatingSystemVersion,
        metalSupport: MetalSupport
    ) {
        self.chip = chip
        self.totalMemoryBytes = totalMemoryBytes
        self.gpuCoreCount = gpuCoreCount
        self.cpuCoreCount = cpuCoreCount
        self.cpuPerformanceCores = cpuPerformanceCores
        self.cpuEfficiencyCores = cpuEfficiencyCores
        self.neuralEngineCoreCount = neuralEngineCoreCount
        self.osVersion = osVersion
        self.metalSupport = metalSupport
    }

    public var totalMemoryGB: Double {
        Double(totalMemoryBytes) / 1_073_741_824
    }

    public var hasNeuralEngine: Bool {
        neuralEngineCoreCount > 0
    }

    /// Usable memory for model inference after reserving system headroom.
    /// Formula: `min(0.85 × total, total − 2 GB)`, floored at 1 GB.
    /// Calibrated against llm-checker's Apple Silicon unified-memory formula.
    public var availableMemoryForInferenceBytes: UInt64 {
        let total = Double(totalMemoryBytes)
        let oneGB = 1_073_741_824.0
        let usable = Swift.min(0.85 * total, total - 2.0 * oneGB)
        return UInt64(Swift.max(oneGB, usable))
    }
}

// MARK: - OperatingSystemVersion conformances

extension OperatingSystemVersion: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case majorVersion, minorVersion, patchVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            majorVersion: try container.decode(Int.self, forKey: .majorVersion),
            minorVersion: try container.decode(Int.self, forKey: .minorVersion),
            patchVersion: try container.decode(Int.self, forKey: .patchVersion)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(majorVersion, forKey: .majorVersion)
        try container.encode(minorVersion, forKey: .minorVersion)
        try container.encode(patchVersion, forKey: .patchVersion)
    }
}

extension OperatingSystemVersion: @retroactive Equatable {
    public static func == (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        lhs.majorVersion == rhs.majorVersion
            && lhs.minorVersion == rhs.minorVersion
            && lhs.patchVersion == rhs.patchVersion
    }
}

extension OperatingSystemVersion: @retroactive @unchecked Sendable {}
