import Foundation

struct ModelsDevProvider: Codable, Sendable {
    let name: String?
    let doc: String?
    let models: [String: ModelsDevModel]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        doc = try container.decodeIfPresent(String.self, forKey: .doc)
        models = (try? container.decode([String: ModelsDevModel].self, forKey: .models)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case name, doc, models
    }
}

struct ModelsDevModel: Codable, Sendable {
    let name: String?
    let family: String?
    let openWeights: Bool?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case name, family
        case openWeights = "open_weights"
        case releaseDate = "release_date"
    }
}

struct ModelsDevEntry: Sendable {
    let fullID: String
    let providerID: String
    let modelID: String
    let name: String
    let family: String?
    let releaseDate: String?
    let providerName: String?
    let providerDoc: String?
}
