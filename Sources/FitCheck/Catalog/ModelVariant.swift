import Foundation

public struct ModelVariant: Sendable, Identifiable, Codable, Equatable {
    public let id: String
    public let quantization: QuantizationFormat
    public let sizeBytes: UInt64
    public let requirements: ModelRequirements
    public let ollamaTag: String?
    public let lmStudioModelID: String?
    public let mlxModelID: String?
    public let downloadURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, quantization, sizeBytes, requirements, ollamaTag
        case lmStudioModelID = "lmStudioModelId"
        case mlxModelID = "mlxModelId"
        case downloadURL = "downloadUrl"
    }

    public init(
        id: String,
        quantization: QuantizationFormat,
        sizeBytes: UInt64,
        requirements: ModelRequirements,
        ollamaTag: String?,
        lmStudioModelID: String?,
        mlxModelID: String? = nil,
        downloadURL: URL?
    ) {
        self.id = id
        self.quantization = quantization
        self.sizeBytes = sizeBytes
        self.requirements = requirements
        self.ollamaTag = ollamaTag
        self.lmStudioModelID = lmStudioModelID
        self.mlxModelID = mlxModelID
        self.downloadURL = downloadURL
    }

    public var sizeGB: Double {
        Double(sizeBytes) / 1_073_741_824
    }

    public var sizeDisplayString: String {
        String(format: "%.1f GB", sizeGB)
    }
}

// MARK: - ModelRequirements

public struct ModelRequirements: Sendable, Codable, Equatable {
    public let minimumMemoryBytes: UInt64
    public let recommendedMemoryBytes: UInt64
    public let diskSizeBytes: UInt64

    public init(minimumMemoryBytes: UInt64, recommendedMemoryBytes: UInt64, diskSizeBytes: UInt64) {
        self.minimumMemoryBytes = minimumMemoryBytes
        self.recommendedMemoryBytes = recommendedMemoryBytes
        self.diskSizeBytes = diskSizeBytes
    }

    public var minimumMemoryGB: Double {
        Double(minimumMemoryBytes) / 1_073_741_824
    }

    public var recommendedMemoryGB: Double {
        Double(recommendedMemoryBytes) / 1_073_741_824
    }

    public var diskSizeGB: Double {
        Double(diskSizeBytes) / 1_073_741_824
    }
}

// MARK: - Requirement estimation (calibrated formula)

extension ModelRequirements {
    public static let defaultContextLength: UInt64 = 4096
    public static let runtimeOverheadBytes: UInt64 = 500 * 1_048_576

    /// Estimate memory requirements from parameter count and quantization format.
    /// Uses calibrated `gbPerBillionParams` values validated against real Ollama sizes.
    public static func estimated(
        parameterCount: ParameterCount,
        quantization: QuantizationFormat,
        diskSizeBytes: UInt64,
        contextLength: UInt64 = defaultContextLength
    ) -> ModelRequirements {
        let oneGB: Double = 1_073_741_824

        let modelWeightsBytes = UInt64(
            parameterCount.billions * quantization.gbPerBillionParams * oneGB
        )

        let kvCacheBytes = UInt64(
            0.000008 * parameterCount.billions * Double(contextLength) * oneGB
        )

        let minimum = modelWeightsBytes + kvCacheBytes + runtimeOverheadBytes
        let recommended = UInt64(Double(minimum) * 1.2)

        return ModelRequirements(
            minimumMemoryBytes: minimum,
            recommendedMemoryBytes: recommended,
            diskSizeBytes: diskSizeBytes
        )
    }
}
