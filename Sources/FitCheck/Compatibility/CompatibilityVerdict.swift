public enum CompatibilityVerdict: Sendable, Equatable, CustomStringConvertible {
    case compatible(PerformanceTier)
    case marginal
    case incompatible(IncompatibilityReason)

    public var isRunnable: Bool {
        switch self {
        case .compatible, .marginal: true
        case .incompatible:          false
        }
    }

    public var description: String {
        switch self {
        case .compatible(let tier):
            "Compatible (\(tier.displayName))"
        case .marginal:
            "Marginal — model fits but swapping is likely"
        case .incompatible(let reason):
            "Incompatible — \(reason.displayDescription)"
        }
    }
}

public enum PerformanceTier: Int, Sendable, Codable, Comparable, CaseIterable {
    case optimal = 3
    case comfortable = 2
    case constrained = 1

    public static func < (lhs: PerformanceTier, rhs: PerformanceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .optimal:     "Optimal"
        case .comfortable: "Comfortable"
        case .constrained: "Constrained"
        }
    }

    public var displayDescription: String {
        switch self {
        case .optimal:
            "Model fits well within available memory. Expect smooth, fast inference."
        case .comfortable:
            "Model runs with adequate headroom. Good performance for most tasks."
        case .constrained:
            "Model fits but memory is tight. Expect slower inference with long contexts."
        }
    }
}

public enum IncompatibilityReason: Sendable, Equatable {
    case insufficientMemory(requiredBytes: UInt64, availableBytes: UInt64)

    public var displayDescription: String {
        switch self {
        case .insufficientMemory(let required, let available):
            let reqGB = String(format: "%.1f", Double(required) / 1_073_741_824)
            let avlGB = String(format: "%.1f", Double(available) / 1_073_741_824)
            return "Requires \(reqGB) GB but only \(avlGB) GB available for inference"
        }
    }
}
