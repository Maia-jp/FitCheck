import Foundation

struct CatalogOutput: Codable, Sendable {
    let version: String
    let generatedAt: String
    var models: [CatalogModel]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case models
    }
}

struct CatalogModel: Codable, Sendable {
    let id: String
    let name: String
    let family: String
    let parameterCount: CatalogParameterCount
    let description: String
    let license: CatalogLicense
    let releaseDate: String?
    let sourceUrl: String?
    let huggingFaceUrl: String?
    var variants: [CatalogVariant]

    enum CodingKeys: String, CodingKey {
        case id, name, family, description, license, variants
        case parameterCount = "parameter_count"
        case releaseDate = "release_date"
        case sourceUrl = "source_url"
        case huggingFaceUrl = "hugging_face_url"
    }
}

struct CatalogParameterCount: Codable, Sendable {
    let billions: Double
}

struct CatalogLicense: Codable, Sendable {
    let identifier: String
    let name: String
    let url: String?
    let isOpenSource: Bool

    enum CodingKeys: String, CodingKey {
        case identifier, name, url
        case isOpenSource = "is_open_source"
    }
}

struct CatalogVariant: Codable, Sendable {
    let id: String
    let quantization: String
    let sizeBytes: UInt64
    let requirements: CatalogRequirements
    let ollamaTag: String?
    let lmStudioModelId: String?
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, quantization, requirements
        case sizeBytes = "size_bytes"
        case ollamaTag = "ollama_tag"
        case lmStudioModelId = "lm_studio_model_id"
        case downloadUrl = "download_url"
    }
}

struct CatalogRequirements: Codable, Sendable {
    let minimumMemoryBytes: UInt64
    let recommendedMemoryBytes: UInt64
    let diskSizeBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case minimumMemoryBytes = "minimum_memory_bytes"
        case recommendedMemoryBytes = "recommended_memory_bytes"
        case diskSizeBytes = "disk_size_bytes"
    }
}
