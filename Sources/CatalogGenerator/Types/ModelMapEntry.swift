import Foundation

struct ModelMapEntry: Codable, Sendable {
    let ollama: String
    let hfGguf: String?
    let paramsB: Double

    enum CodingKeys: String, CodingKey {
        case ollama
        case hfGguf = "hf_gguf"
        case paramsB = "params_b"
    }
}
