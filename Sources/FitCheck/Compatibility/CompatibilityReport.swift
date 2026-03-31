public struct CompatibilityReport: Sendable, Equatable {
    public let modelCardID: String
    public let variantID: String
    public let verdict: CompatibilityVerdict
    public let estimatedMemoryUsageBytes: UInt64
    public let availableMemoryBytes: UInt64
    public let memoryHeadroomBytes: Int64
    public let memoryUsagePercent: Double
    public let warnings: [CompatibilityWarning]

    public init(
        modelCardID: String, variantID: String, verdict: CompatibilityVerdict,
        estimatedMemoryUsageBytes: UInt64, availableMemoryBytes: UInt64,
        memoryHeadroomBytes: Int64, memoryUsagePercent: Double,
        warnings: [CompatibilityWarning]
    ) {
        self.modelCardID = modelCardID
        self.variantID = variantID
        self.verdict = verdict
        self.estimatedMemoryUsageBytes = estimatedMemoryUsageBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.memoryHeadroomBytes = memoryHeadroomBytes
        self.memoryUsagePercent = memoryUsagePercent
        self.warnings = warnings
    }

    public var memoryHeadroomGB: Double {
        Double(memoryHeadroomBytes) / 1_073_741_824
    }

    public var estimatedMemoryUsageGB: Double {
        Double(estimatedMemoryUsageBytes) / 1_073_741_824
    }
}

public enum CompatibilityWarning: Sendable, Equatable {
    case tightMemoryFit(usagePercent: Double)
    case swappingLikely
    case smallerQuantizationAvailable(QuantizationFormat)

    public var displayMessage: String {
        switch self {
        case .tightMemoryFit(let percent):
            String(format: "Memory usage at %.0f%% — close other apps for best performance", percent)
        case .swappingLikely:
            "Model may require disk swap, significantly reducing inference speed"
        case .smallerQuantizationAvailable(let format):
            "A smaller quantization (\(format.displayName)) is available and may run better"
        }
    }
}
