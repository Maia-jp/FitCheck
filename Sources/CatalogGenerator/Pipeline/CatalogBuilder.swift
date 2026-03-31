import Foundation

enum CatalogBuilder {
    static let targetQuantizations = ["Q4_K_M", "Q5_K_M", "Q8_0", "Q3_K_M", "Q6_K", "Q2_K", "F16"]

    static func buildCard(
        from entry: ModelsDevEntry,
        mapping: ModelMapEntry
    ) -> CatalogModel {
        CatalogModel(
            id: entry.modelID,
            name: entry.name,
            family: entry.family ?? "other",
            parameterCount: CatalogParameterCount(billions: mapping.paramsB),
            description: "\(entry.name) by \(entry.providerName ?? entry.providerID).",
            license: CatalogLicense(
                identifier: entry.family ?? "unknown",
                name: "\(entry.name) License",
                url: nil,
                isOpenSource: true
            ),
            releaseDate: entry.releaseDate,
            sourceUrl: entry.providerDoc,
            huggingFaceUrl: mapping.hfGguf.map { "https://huggingface.co/\($0)" },
            variants: buildFormulaVariants(
                modelID: entry.modelID,
                ollamaBase: mapping.ollama,
                hfGguf: mapping.hfGguf,
                paramsB: mapping.paramsB
            )
        )
    }

    static func buildFormulaVariants(
        modelID: String,
        ollamaBase: String,
        hfGguf: String?,
        paramsB: Double
    ) -> [CatalogVariant] {
        targetQuantizations.compactMap { quant in
            let tag = "\(ollamaBase.split(separator: ":").first ?? Substring(ollamaBase)):\(quant.lowercased())"
            let sizeBytes = UInt64(paramsB * gbPerBillionParams(quant) * 1_073_741_824)
            let requirements = RequirementsCalculator.compute(
                paramsBillion: paramsB,
                quantization: quant,
                diskSizeBytes: sizeBytes
            )

            return CatalogVariant(
                id: "\(modelID)-\(quant.lowercased().replacingOccurrences(of: "_", with: ""))",
                quantization: quant,
                sizeBytes: sizeBytes,
                requirements: requirements,
                ollamaTag: tag,
                lmStudioModelId: hfGguf,
                downloadUrl: hfGguf.map { "https://huggingface.co/\($0)" }
            )
        }
    }

    private static func gbPerBillionParams(_ quant: String) -> Double {
        let table: [String: Double] = [
            "Q2_K": 0.37, "Q3_K_M": 0.48, "Q4_K_M": 0.58,
            "Q5_K_M": 0.68, "Q6_K": 0.80, "Q8_0": 1.05, "F16": 2.00,
        ]
        return table[quant] ?? 0.58
    }
}
