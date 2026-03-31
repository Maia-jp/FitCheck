import Foundation

enum RequirementsCalculator {
    private static let gbPerBillionParams: [String: Double] = [
        "Q2_K": 0.37,  "Q3_K_S": 0.44, "Q3_K_M": 0.48,
        "Q4_0": 0.54,  "Q4_K_S": 0.56, "Q4_K_M": 0.58,
        "Q5_0": 0.63,  "Q5_K_S": 0.66, "Q5_K_M": 0.68,
        "Q6_K": 0.80,  "Q8_0":   1.05,
        "F16":  2.00,  "F32":    4.00,
    ]

    private static let defaultContextLength: Double = 4096
    private static let runtimeOverheadGB: Double = 0.5
    private static let kvCacheFactorPerBPerToken: Double = 0.000008

    static func compute(
        paramsBillion: Double,
        quantization: String,
        diskSizeBytes: UInt64
    ) -> CatalogRequirements {
        let gbpp = gbPerBillionParams[quantization] ?? 0.58
        let weightsGB = paramsBillion * gbpp
        let kvCacheGB = kvCacheFactorPerBPerToken * paramsBillion * defaultContextLength
        let minimumGB = weightsGB + kvCacheGB + runtimeOverheadGB
        let recommendedGB = minimumGB * 1.2

        let oneGB: UInt64 = 1_073_741_824
        return CatalogRequirements(
            minimumMemoryBytes: UInt64(minimumGB * Double(oneGB)),
            recommendedMemoryBytes: UInt64(recommendedGB * Double(oneGB)),
            diskSizeBytes: diskSizeBytes
        )
    }
}
