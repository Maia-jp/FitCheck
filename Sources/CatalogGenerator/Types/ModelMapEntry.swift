import Foundation

struct ModelMapEntry: Codable, Sendable {
    let ollama: String
    let hfGguf: String?
    let paramsB: Double
    let activeParamsB: Double?
    let displayName: String?
    let family: String?
    let contextLength: Int?
    let useCase: String?
    let capabilities: [String]?

    var effectiveParamsB: Double { activeParamsB ?? paramsB }
    var isMoE: Bool { activeParamsB != nil }

    enum CodingKeys: String, CodingKey {
        case ollama
        case hfGguf = "hf_gguf"
        case paramsB = "params_b"
        case activeParamsB = "active_params_b"
        case displayName = "name"
        case family
        case contextLength = "context_length"
        case useCase = "use_case"
        case capabilities
    }
}
