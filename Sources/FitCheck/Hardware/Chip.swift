public enum Chip: Sendable, Equatable, Codable {
    case appleSilicon(AppleSiliconVariant)
    case unknown(String)
}

public enum AppleSiliconVariant: String, Sendable, Codable, CaseIterable {
    case m1
    case m1Pro = "m1_pro"
    case m1Max = "m1_max"
    case m1Ultra = "m1_ultra"
    case m2
    case m2Pro = "m2_pro"
    case m2Max = "m2_max"
    case m2Ultra = "m2_ultra"
    case m3
    case m3Pro = "m3_pro"
    case m3Max = "m3_max"
    case m3Ultra = "m3_ultra"
    case m4
    case m4Pro = "m4_pro"
    case m4Max = "m4_max"
    case m4Ultra = "m4_ultra"

    public var family: ChipFamily {
        switch self {
        case .m1, .m1Pro, .m1Max, .m1Ultra: .m1
        case .m2, .m2Pro, .m2Max, .m2Ultra: .m2
        case .m3, .m3Pro, .m3Max, .m3Ultra: .m3
        case .m4, .m4Pro, .m4Max, .m4Ultra: .m4
        }
    }

    public var tier: ChipTier {
        switch self {
        case .m1, .m2, .m3, .m4:                    .base
        case .m1Pro, .m2Pro, .m3Pro, .m4Pro:         .pro
        case .m1Max, .m2Max, .m3Max, .m4Max:         .max
        case .m1Ultra, .m2Ultra, .m3Ultra, .m4Ultra: .ultra
        }
    }
}

public enum ChipFamily: String, Sendable, Codable, CaseIterable, Comparable {
    case m1, m2, m3, m4

    public static func < (lhs: ChipFamily, rhs: ChipFamily) -> Bool {
        lhs.generationIndex < rhs.generationIndex
    }

    internal var generationIndex: Int {
        switch self {
        case .m1: 1
        case .m2: 2
        case .m3: 3
        case .m4: 4
        }
    }
}

public enum ChipTier: Int, Sendable, Codable, Comparable, CaseIterable {
    case base = 0
    case pro = 1
    case max = 2
    case ultra = 3

    public static func < (lhs: ChipTier, rhs: ChipTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
