public enum QuantizationFormat: String, Sendable, Codable, CaseIterable, Equatable, Comparable {
    case q2K   = "Q2_K"
    case q3KS  = "Q3_K_S"
    case q3KM  = "Q3_K_M"
    case q4_0  = "Q4_0"
    case q4KS  = "Q4_K_S"
    case q4KM  = "Q4_K_M"
    case q5_0  = "Q5_0"
    case q5KS  = "Q5_K_S"
    case q5KM  = "Q5_K_M"
    case q6K   = "Q6_K"
    case q8_0  = "Q8_0"
    case f16   = "F16"
    case f32   = "F32"

    /// Calibrated GB consumed per billion parameters.
    /// Values validated against real Ollama download sizes
    /// and aligned with llm-checker's calibration table.
    public var gbPerBillionParams: Double {
        switch self {
        case .q2K:  0.37
        case .q3KS: 0.44
        case .q3KM: 0.48
        case .q4_0: 0.54
        case .q4KS: 0.56
        case .q4KM: 0.58
        case .q5_0: 0.63
        case .q5KS: 0.66
        case .q5KM: 0.68
        case .q6K:  0.80
        case .q8_0: 1.05
        case .f16:  2.00
        case .f32:  4.00
        }
    }

    /// Derived from `gbPerBillionParams`.
    public var bitsPerWeight: Double {
        gbPerBillionParams * 8
    }

    public var displayName: String { rawValue }

    public var qualityTier: QuantizationQuality {
        switch self {
        case .q2K, .q3KS, .q3KM:                .low
        case .q4_0, .q4KS, .q4KM:               .medium
        case .q5_0, .q5KS, .q5KM, .q6K:         .high
        case .q8_0, .f16, .f32:                  .nearLossless
        }
    }

    public static func < (lhs: QuantizationFormat, rhs: QuantizationFormat) -> Bool {
        lhs.gbPerBillionParams < rhs.gbPerBillionParams
    }
}

public enum QuantizationQuality: String, Sendable, Codable, Comparable {
    case low
    case medium
    case high
    case nearLossless = "near_lossless"

    public static func < (lhs: QuantizationQuality, rhs: QuantizationQuality) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    internal var sortOrder: Int {
        switch self {
        case .low:          0
        case .medium:       1
        case .high:         2
        case .nearLossless: 3
        }
    }
}
