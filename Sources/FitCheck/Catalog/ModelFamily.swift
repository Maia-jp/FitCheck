public enum ModelFamily: String, Sendable, Codable, CaseIterable, Equatable {
    case llama
    case codeLlama = "code_llama"
    case mistral
    case mixtral
    case phi
    case gemma
    case qwen
    case deepseek
    case starcoder
    case falcon
    case yi
    case vicuna
    case commandR = "command_r"
    case olmo
    case internLM = "intern_lm"
    case smolLM = "smol_lm"
    case granite
    case nemotron
    case aya
    case cogito
    case glm
    case gptOss = "gpt_oss"
    case lfm
    case solar
    case dolphin
    case hermes
    case wizard
    case openchat
    case other

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ModelFamily(rawValue: rawValue) ?? .other
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .llama:      "Llama"
        case .codeLlama:  "Code Llama"
        case .mistral:    "Mistral"
        case .mixtral:    "Mixtral"
        case .phi:        "Phi"
        case .gemma:      "Gemma"
        case .qwen:       "Qwen"
        case .deepseek:   "DeepSeek"
        case .starcoder:  "StarCoder"
        case .falcon:     "Falcon"
        case .yi:         "Yi"
        case .vicuna:     "Vicuna"
        case .commandR:   "Command R"
        case .olmo:       "OLMo"
        case .internLM:   "InternLM"
        case .smolLM:     "SmolLM"
        case .granite:    "Granite"
        case .nemotron:   "Nemotron"
        case .aya:        "Aya"
        case .cogito:     "Cogito"
        case .glm:        "GLM"
        case .gptOss:     "GPT-OSS"
        case .lfm:        "LFM"
        case .solar:      "Solar"
        case .dolphin:    "Dolphin"
        case .hermes:     "Hermes"
        case .wizard:     "WizardLM"
        case .openchat:   "OpenChat"
        case .other:      "Other"
        }
    }
}
