import Foundation
import Testing
@testable import FitCheck

// MARK: - Test fixtures

struct MockCatalogProvider: CatalogProvider {
    let models: [ModelCard]
    let error: FitCheckError?

    init(models: [ModelCard] = [], error: FitCheckError? = nil) {
        self.models = models
        self.error = error
    }

    func fetchModels() async throws -> [ModelCard] {
        if let error { throw error }
        return models
    }
}

extension ModelCard {
    static func fixture(
        id: String = "test-model-7b",
        name: String = "Test Model",
        family: ModelFamily = .llama,
        parameterCount: ParameterCount = ParameterCount(billions: 7),
        variants: [ModelVariant] = [.fixture()]
    ) -> ModelCard {
        ModelCard(
            id: id,
            name: name,
            family: family,
            parameterCount: parameterCount,
            description: "A test model for unit testing.",
            license: ModelLicense(
                identifier: "mit",
                name: "MIT License",
                url: URL(string: "https://opensource.org/licenses/MIT"),
                isOpenSource: true
            ),
            releaseDate: "2024-01-01",
            sourceURL: nil,
            huggingFaceURL: nil,
            variants: variants
        )
    }
}

extension ModelVariant {
    static func fixture(
        id: String = "test-model-7b-q4km",
        quantization: QuantizationFormat = .q4KM,
        sizeBytes: UInt64 = 4_200_000_000,
        minimumMemoryBytes: UInt64 = 5_700_000_000,
        recommendedMemoryBytes: UInt64 = 7_125_000_000,
        ollamaTag: String? = "test-model:7b-q4_K_M",
        lmStudioModelID: String? = "test/test-model-7b-GGUF"
    ) -> ModelVariant {
        ModelVariant(
            id: id,
            quantization: quantization,
            sizeBytes: sizeBytes,
            requirements: ModelRequirements(
                minimumMemoryBytes: minimumMemoryBytes,
                recommendedMemoryBytes: recommendedMemoryBytes,
                diskSizeBytes: sizeBytes
            ),
            ollamaTag: ollamaTag,
            lmStudioModelID: lmStudioModelID,
            downloadURL: nil
        )
    }
}

// MARK: - ParameterCount tests

@Suite("ParameterCount")
struct ParameterCountTests {
    @Test("Display string for billion-scale models")
    func billionDisplay() {
        #expect(ParameterCount(billions: 7).displayString == "7B")
        #expect(ParameterCount(billions: 70).displayString == "70B")
        #expect(ParameterCount(billions: 3.8).displayString == "3.8B")
    }

    @Test("Display string for sub-billion models")
    func millionDisplay() {
        #expect(ParameterCount(billions: 0.5).displayString == "500M")
        #expect(ParameterCount(billions: 0.125).displayString == "125M")
    }

    @Test("Ordering is by parameter count")
    func ordering() {
        #expect(ParameterCount(billions: 3) < ParameterCount(billions: 7))
        #expect(ParameterCount(billions: 70) > ParameterCount(billions: 13))
    }
}

// MARK: - QuantizationFormat tests

@Suite("QuantizationFormat")
struct QuantizationFormatTests {
    @Test("Calibrated GB per billion params values")
    func gbPerBillionParams() {
        #expect(QuantizationFormat.q4KM.gbPerBillionParams == 0.58)
        #expect(QuantizationFormat.q8_0.gbPerBillionParams == 1.05)
        #expect(QuantizationFormat.f16.gbPerBillionParams == 2.00)
    }

    @Test("bitsPerWeight is derived from gbPerBillionParams")
    func bitsPerWeight() {
        #expect(QuantizationFormat.q4KM.bitsPerWeight == 0.58 * 8)
        #expect(QuantizationFormat.f16.bitsPerWeight == 16.0)
    }

    @Test("Ordering is by gbPerBillionParams")
    func ordering() {
        #expect(QuantizationFormat.q2K < .q4KM)
        #expect(QuantizationFormat.q4KM < .q8_0)
        #expect(QuantizationFormat.q8_0 < .f16)
    }

    @Test("Quality tier categorization")
    func qualityTiers() {
        #expect(QuantizationFormat.q2K.qualityTier == .low)
        #expect(QuantizationFormat.q4KM.qualityTier == .medium)
        #expect(QuantizationFormat.q5KM.qualityTier == .high)
        #expect(QuantizationFormat.q8_0.qualityTier == .nearLossless)
    }
}

// MARK: - ModelFamily tests

@Suite("ModelFamily")
struct ModelFamilyTests {
    @Test("Unknown family decodes to .other")
    func unknownFamily() throws {
        let json = "\"some_new_family\""
        let decoded = try JSONDecoder().decode(ModelFamily.self, from: Data(json.utf8))
        #expect(decoded == .other)
    }

    @Test("Known family decodes correctly")
    func knownFamily() throws {
        let json = "\"llama\""
        let decoded = try JSONDecoder().decode(ModelFamily.self, from: Data(json.utf8))
        #expect(decoded == .llama)
    }
}

// MARK: - ModelRequirements estimation tests

@Suite("ModelRequirements estimation")
struct ModelRequirementsEstimationTests {
    @Test("Estimated requirements for 7B Q4_K_M model")
    func estimate7B() {
        let req = ModelRequirements.estimated(
            parameterCount: ParameterCount(billions: 7),
            quantization: .q4KM,
            diskSizeBytes: 4_200_000_000
        )
        #expect(req.minimumMemoryGB > 4.0)
        #expect(req.minimumMemoryGB < 6.0)
        #expect(req.recommendedMemoryGB > req.minimumMemoryGB)
    }

    @Test("KV cache scales with model size")
    func kvCacheScaling() {
        let small = ModelRequirements.estimated(
            parameterCount: ParameterCount(billions: 3),
            quantization: .q4KM,
            diskSizeBytes: 2_000_000_000
        )
        let large = ModelRequirements.estimated(
            parameterCount: ParameterCount(billions: 70),
            quantization: .q4KM,
            diskSizeBytes: 40_000_000_000
        )
        let smallOverhead = small.minimumMemoryBytes
            - UInt64(3.0 * 0.58 * 1_073_741_824)
        let largeOverhead = large.minimumMemoryBytes
            - UInt64(70.0 * 0.58 * 1_073_741_824)
        #expect(largeOverhead > smallOverhead)
    }
}

// MARK: - CompositeCatalogProvider tests

@Suite("CompositeCatalogProvider")
struct CompositeCatalogProviderTests {
    @Test("Remote entries override bundled entries with same ID")
    func remoteOverridesBundled() async throws {
        let bundled = MockCatalogProvider(models: [
            .fixture(id: "model-a", name: "Old Name"),
        ])
        let remote = MockCatalogProvider(models: [
            .fixture(id: "model-a", name: "New Name"),
        ])

        let composite = CompositeCatalogProvider(primary: remote, fallback: bundled)
        let models = try await composite.fetchModels()

        #expect(models.count == 1)
        #expect(models[0].name == "New Name")
    }

    @Test("Falls back to bundled when remote fails")
    func fallbackOnRemoteFailure() async throws {
        let bundled = MockCatalogProvider(models: [.fixture(id: "model-b")])
        let remote = MockCatalogProvider(
            error: .networkUnavailable(underlying: URLError(.notConnectedToInternet))
        )

        let composite = CompositeCatalogProvider(primary: remote, fallback: bundled)
        let models = try await composite.fetchModels()

        #expect(models.count == 1)
        #expect(models[0].id == "model-b")
    }

    @Test("Merges unique models from both sources")
    func mergeUnique() async throws {
        let bundled = MockCatalogProvider(models: [.fixture(id: "a", name: "Model A")])
        let remote = MockCatalogProvider(models: [.fixture(id: "b", name: "Model B")])

        let composite = CompositeCatalogProvider(primary: remote, fallback: bundled)
        let models = try await composite.fetchModels()

        #expect(models.count == 2)
    }
}

// MARK: - BundledCatalogProvider tests

@Suite("BundledCatalogProvider")
struct BundledCatalogProviderTests {
    @Test("Bundled catalog loads without error")
    func loadsSuccessfully() async throws {
        let provider = BundledCatalogProvider()
        let models = try await provider.fetchModels()
        #expect(models is [ModelCard])
    }
}

// MARK: - Codable round-trip

@Suite("Catalog Codable")
struct CatalogCodableTests {
    @Test("ModelCard round-trips through JSON with snake_case keys")
    func modelCardRoundTrip() throws {
        let card = ModelCard.fixture()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(card)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ModelCard.self, from: data)

        #expect(decoded == card)
    }
}
