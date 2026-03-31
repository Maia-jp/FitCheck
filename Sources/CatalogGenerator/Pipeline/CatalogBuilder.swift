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
        "cogito": "Deep Cogito",
        "glm": "Zhipu AI",
        "gpt_oss": "OpenAI",
        "lfm": "Liquid AI",
        "solar": "Upstage",
        "dolphin": "Cognitive Computations",
        "hermes": "Nous Research",
        "wizard": "WizardLM Team",
        "openchat": "OpenChat Team",
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

        let moeNote = mapping.isMoE
            ? " MoE model: \(String(format: "%.0f", mapping.paramsB))B total, \(String(format: "%.0f", mapping.effectiveParamsB))B active."
            : ""

        let useCase = mapping.useCase ?? inferUseCase(name: name, ollama: ollamaTag)
        let capabilities = mapping.capabilities ?? inferCapabilities(name: name, useCase: useCase)
        let contextLength = mapping.contextLength

        return CatalogModel(
            id: cleanID,
            name: name,
            family: family,
            parameterCount: CatalogParameterCount(billions: mapping.paramsB),
            description: description + moeNote,
            license: CatalogLicense(
                identifier: family,
                name: "\(name) License",
                url: nil,
                isOpenSource: true
            ),
            releaseDate: entry.releaseDate,
            sourceUrl: entry.providerDoc,
            huggingFaceUrl: mapping.hfGguf.map { "https://huggingface.co/\($0)" },
            contextLength: contextLength,
            useCase: useCase,
            capabilities: capabilities.isEmpty ? nil : capabilities,
            isMoE: mapping.isMoE ? true : nil,
            variants: buildFormulaVariants(
                modelID: cleanID,
                ollamaTag: ollamaTag,
                hfGguf: mapping.hfGguf,
                mlxModel: mapping.mlxModel,
                totalParamsB: mapping.paramsB,
                activeParamsB: mapping.effectiveParamsB
            )
        )
    }

    /// Each variant represents a different quantization at a known size.
    /// The `ollamaTag` is the real pull tag from the model map — what
    /// users actually type into `ollama pull`.
    /// `totalParamsB` is used for disk size estimation (all weights are stored).
    /// `activeParamsB` is used for memory requirements (MoE models only load active experts).
    static func buildFormulaVariants(
        modelID: String,
        ollamaTag: String,
        hfGguf: String?,
        mlxModel: String?,
        totalParamsB: Double,
        activeParamsB: Double
    ) -> [CatalogVariant] {
        targetQuantizations.map { quant in
            let sizeBytes = UInt64(totalParamsB * gbPerBillionParams(quant) * 1_073_741_824)
            let requirements = RequirementsCalculator.compute(
                paramsBillion: activeParamsB,
                quantization: quant,
                diskSizeBytes: sizeBytes
            )

            return CatalogVariant(
                id: "\(modelID)-\(quant.lowercased().replacingOccurrences(of: "_", with: ""))",
                quantization: quant,
                sizeBytes: sizeBytes,
                requirements: requirements,
                ollamaTag: ollamaTag,
                lmStudioModelId: hfGguf,
                mlxModelId: mlxModel,
                downloadUrl: hfGguf.map { "https://huggingface.co/\($0)" }
            )
        }
    }

    // MARK: - Use case and capability inference (aligned with LLMfit's approach)

    static func inferUseCase(name: String, ollama: String) -> String {
        let lower = (name + " " + ollama).lowercased()
        if lower.contains("embed") || lower.contains("bge") { return "Text embeddings" }
        if lower.contains("coder") || lower.contains("starcoder") || lower.contains("codellama") || lower.contains("codestral") || lower.contains("codegemma") || lower.contains("deepcoder") { return "Code generation" }
        if lower.contains("r1") || lower.contains("reason") || lower.contains("qwq") || lower.contains("deepscaler") { return "Reasoning" }
        if lower.contains("instruct") || lower.contains("chat") || lower.contains("dolphin") || lower.contains("hermes") || lower.contains("vicuna") || lower.contains("openchat") { return "Chat" }
        if lower.contains("tiny") || lower.contains("small") || lower.contains("mini") || lower.contains("smol") { return "Lightweight" }
        return "General purpose"
    }

    static func inferCapabilities(name: String, useCase: String) -> [String] {
        var caps: [String] = []
        let lower = (name + " " + useCase).lowercased()
        if lower.contains("vision") || lower.contains("-vl") || lower.contains("llava") || lower.contains("pixtral") { caps.append("vision") }
        if lower.contains("tool") || lower.contains("qwen3") || lower.contains("qwen2.5") || lower.contains("command-r") || lower.contains("hermes") || lower.contains("mistral") { caps.append("tool_use") }
        return caps
    }

    private static func gbPerBillionParams(_ quant: String) -> Double {
        let table: [String: Double] = [
            "Q2_K": 0.37, "Q3_K_M": 0.48, "Q4_K_M": 0.58,
            "Q5_K_M": 0.68, "Q6_K": 0.80, "Q8_0": 1.05, "F16": 2.00,
        ]
        return table[quant] ?? 0.58
    }
}
