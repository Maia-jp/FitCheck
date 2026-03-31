import Foundation

public struct ModelCard: Sendable, Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let family: ModelFamily
    public let parameterCount: ParameterCount
    public let description: String
    public let license: ModelLicense
    public let releaseDate: String?
    public let sourceURL: URL?
    public let huggingFaceURL: URL?
    public let variants: [ModelVariant]

    enum CodingKeys: String, CodingKey {
        case id, name, family, parameterCount, description, license
        case releaseDate, variants
        case sourceURL = "sourceUrl"
        case huggingFaceURL = "huggingFaceUrl"
    }

    public init(
        id: String,
        name: String,
        family: ModelFamily,
        parameterCount: ParameterCount,
        description: String,
        license: ModelLicense,
        releaseDate: String?,
        sourceURL: URL?,
        huggingFaceURL: URL?,
        variants: [ModelVariant]
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.parameterCount = parameterCount
        self.description = description
        self.license = license
        self.releaseDate = releaseDate
        self.sourceURL = sourceURL
        self.huggingFaceURL = huggingFaceURL
        self.variants = variants
    }

    public var displayName: String {
        "\(name) \(parameterCount.displayString)"
    }

    public var bestQuantizationVariant: ModelVariant? {
        variants
            .sorted { $0.quantization.gbPerBillionParams > $1.quantization.gbPerBillionParams }
            .first
    }

    public var smallestVariant: ModelVariant? {
        variants
            .sorted { $0.sizeBytes < $1.sizeBytes }
            .first
    }
}

// MARK: - ParameterCount

public struct ParameterCount: Sendable, Codable, Equatable, Comparable, Hashable {
    public let billions: Double

    public init(billions: Double) {
        self.billions = billions
    }

    public var displayString: String {
        if billions >= 1 {
            let formatted = billions.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", billions)
                : String(format: "%.1f", billions)
            return "\(formatted)B"
        } else {
            return String(format: "%.0fM", billions * 1000)
        }
    }

    public var raw: UInt64 {
        UInt64(billions * 1_000_000_000)
    }

    public static func < (lhs: ParameterCount, rhs: ParameterCount) -> Bool {
        lhs.billions < rhs.billions
    }
}
