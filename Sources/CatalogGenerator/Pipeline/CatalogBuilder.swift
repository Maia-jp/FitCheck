import Foundation

enum CatalogBuilder {
    static let targetQuantizations = ["Q4_K_M", "Q5_K_M", "Q8_0", "Q3_K_M", "Q6_K", "Q2_K", "F16"]

    private static let familyCreators: [String: String] = [
        "llama": "Meta", "code_llama": "Meta",
        "mistral": "Mistral AI", "mixtral": "Mistral AI",
        "phi": "Microsoft",
        "gemma": "Google",
        "qwen": "Alibaba",
        "deepseek": "DeepSeek",
        "falcon": "TII",
        "yi": "01.AI",
        "starcoder": "BigCode",
        "vicuna": "LMSYS",
        "command_r": "Cohere",
        "olmo": "Allen AI",
        "intern_lm": "Shanghai AI Lab",
        "smol_lm": "Hugging Face",
        "granite": "IBM",
        "nemotron": "NVIDIA",
        "aya": "Cohere",
    ]

    static func buildCard(
        from entry: ModelsDevEntry,
        mapping: ModelMapEntry
    ) -> CatalogModel {
        let name = mapping.displayName ?? entry.name
        let family = mapping.family ?? entry.family ?? "other"
        let creator = familyCreators[family]
        let description = creator.map { "\(name) — open-weight model by \($0)." }
            ?? "\(name) — open-weight model."

        let ollamaTag = mapping.ollama
        let cleanID = ollamaTag
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        return CatalogModel(
            id: cleanID,
            name: name,
            family: family,
            parameterCount: CatalogParameterCount(billions: mapping.paramsB),
            description: description,
            license: CatalogLicense(
                identifier: family,
                name: "\(name) License",
                url: nil,
                isOpenSource: true
            ),
            releaseDate: entry.releaseDate,
            sourceUrl: entry.providerDoc,
            huggingFaceUrl: mapping.hfGguf.map { "https://huggingface.co/\($0)" },
            variants: buildFormulaVariants(
                modelID: cleanID,
                ollamaBase: ollamaTag,
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
            let base = ollamaBase.split(separator: ":").first.map(String.init) ?? ollamaBase
            let tag = "\(base):\(quant.lowercased())"
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
