import Foundation

struct ModelMapEntry: Codable, Sendable {
    let ollama: String
    let hfGguf: String?
    let paramsB: Double
    let displayName: String?
    let family: String?

    enum CodingKeys: String, CodingKey {
        case ollama
        case hfGguf = "hf_gguf"
        case paramsB = "params_b"
        case displayName = "name"
        case family
    }
}
