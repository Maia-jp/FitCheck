/// Estimated inference performance for a model on specific hardware.
/// Uses the formula: `tok/s = (bandwidth_GB/s / model_size_GB) * efficiency`.
/// Aligned with LLMfit's approach validated against real benchmarks.
public struct PerformanceEstimate: Sendable, Equatable {
    public let estimatedTokensPerSecond: Double
    public let rating: PerformanceRating
    public let chipBandwidthGBps: Double
    public let modelSizeGB: Double

    public init(
        estimatedTokensPerSecond: Double,
        rating: PerformanceRating,
        chipBandwidthGBps: Double,
        modelSizeGB: Double
    ) {
        self.estimatedTokensPerSecond = estimatedTokensPerSecond
        self.rating = rating
        self.chipBandwidthGBps = chipBandwidthGBps
        self.modelSizeGB = modelSizeGB
    }
}

public enum PerformanceRating: String, Sendable, Equatable, Comparable, CustomStringConvertible {
    case excellent
    case good
    case moderate
    case slow
    case verySlow

    public var description: String {
        switch self {
        case .excellent: "Excellent (>50 tok/s) — real-time conversation"
        case .good:      "Good (30–50 tok/s) — smooth interaction"
        case .moderate:  "Moderate (15–30 tok/s) — usable with slight delays"
        case .slow:      "Slow (8–15 tok/s) — noticeable waiting"
        case .verySlow:  "Very Slow (<8 tok/s) — consider a smaller model"
        }
    }

    public static func < (lhs: PerformanceRating, rhs: PerformanceRating) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .verySlow:  0
        case .slow:      1
        case .moderate:  2
        case .good:      3
        case .excellent: 4
        }
    }
}

// MARK: - Performance calculator

public enum PerformanceCalculator {
    /// Efficiency factor accounting for kernel overhead and KV-cache reads.
    /// Aligned with LLMfit's calibrated value of 0.55.
    private static let efficiencyFactor = 0.55

    public static func estimate(
        modelSizeGB: Double,
        hardware: HardwareProfile
    ) -> PerformanceEstimate {
        let bandwidth = memoryBandwidth(for: hardware.chip)
        let tokPerSec: Double
        if modelSizeGB > 0 {
            tokPerSec = (bandwidth / modelSizeGB) * efficiencyFactor
        } else {
            tokPerSec = 0
        }

        let rating: PerformanceRating = switch tokPerSec {
        case 50...:   .excellent
        case 30..<50: .good
        case 15..<30: .moderate
        case 8..<15:  .slow
        default:      .verySlow
        }

        return PerformanceEstimate(
            estimatedTokensPerSecond: (tokPerSec * 10).rounded() / 10,
            rating: rating,
            chipBandwidthGBps: bandwidth,
            modelSizeGB: modelSizeGB
        )
    }

    /// Memory bandwidth in GB/s per Apple Silicon variant.
    /// Sourced from Apple's published specifications.
    public static func memoryBandwidth(for chip: Chip) -> Double {
        guard case .appleSilicon(let variant) = chip else { return 50 }
        return bandwidthTable[variant] ?? 100
    }

    private static let bandwidthTable: [AppleSiliconVariant: Double] = [
        .m1:       68.25,
        .m1Pro:    200,
        .m1Max:    400,
        .m1Ultra:  800,
        .m2:       100,
        .m2Pro:    200,
        .m2Max:    400,
        .m2Ultra:  800,
        .m3:       100,
        .m3Pro:    150,
        .m3Max:    400,
        .m3Ultra:  800,
        .m4:       120,
        .m4Pro:    273,
        .m4Max:    546,
        .m4Ultra:  819,
    ]
}
