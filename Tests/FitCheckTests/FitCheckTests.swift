import Foundation
import Testing
@testable import FitCheck

// MARK: - FitCheckError tests

@Suite("FitCheckError")
struct FitCheckErrorTests {
    @Test("Error descriptions are non-empty for all cases")
    func errorDescriptions() {
        let cases: [FitCheckError] = [
            .hardwareDetectionFailed(reason: "sysctl failed"),
            .catalogLoadFailed(underlying: URLError(.badURL)),
            .catalogDecodingFailed(path: "/tmp/test.json", underlying: URLError(.cannotDecodeContentData)),
            .networkUnavailable(underlying: URLError(.notConnectedToInternet)),
            .providerNotInstalled(provider: "Ollama"),
            .shellCommandFailed(command: "ollama list", exitCode: 1, stderr: "not found"),
            .modelNotFound(identifier: "nonexistent-model"),
            .unsupportedPlatform(detected: "Intel Mac"),
            .resourceMissing(name: "bundled-catalog.json"),
        ]

        for error in cases {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(!description!.isEmpty)
        }
    }

    @Test("Error conforms to Sendable")
    func sendable() {
        let error: any Sendable = FitCheckError.modelNotFound(identifier: "test")
        #expect(error is FitCheckError)
    }
}

// MARK: - FitCheck integration tests

@Suite("FitCheck Integration")
struct FitCheckIntegrationTests {
    private func makeFitCheck(
        profile: HardwareProfile = .fixture(),
        models: [ModelCard] = [.fixture()]
    ) -> FitCheck {
        FitCheck(
            hardwareProfiler: MockHardwareProfiler(result: .success(profile)),
            catalogProvider: MockCatalogProvider(models: models),
            compatibilityChecker: DefaultCompatibilityChecker(),
            downloadProviders: []
        )
    }

    @Test("compatibleModels returns only runnable models")
    func compatibleModelsFiltering() async throws {
        let smallModel = ModelCard.fixture(
            id: "small",
            variants: [.fixture(id: "s", minimumMemoryBytes: 4 * 1_073_741_824 as UInt64)]
        )
        let hugeModel = ModelCard.fixture(
            id: "huge",
            variants: [.fixture(id: "h", minimumMemoryBytes: 100 * 1_073_741_824 as UInt64)]
        )

        let fc = makeFitCheck(
            profile: .fixture(totalMemoryBytes: 16 * 1_073_741_824),
            models: [smallModel, hugeModel]
        )

        let compatible = try await fc.compatibleModels()
        #expect(compatible.count == 1)
        #expect(compatible[0].card.id == "small")
    }

    @Test("check returns reports for all variants")
    func checkAllVariants() async throws {
        let model = ModelCard.fixture(
            id: "test-model",
            variants: [
                .fixture(id: "v1", quantization: .q4KM),
                .fixture(id: "v2", quantization: .q8_0),
            ]
        )

        let fc = makeFitCheck(models: [model])
        let reports = try await fc.check(modelID: "test-model")
        #expect(reports.count == 2)
    }

    @Test("model(id:) throws for unknown ID")
    func modelNotFound() async {
        let fc = makeFitCheck(models: [])
        do {
            _ = try await fc.model(id: "nonexistent")
            Issue.record("Expected modelNotFound error")
        } catch let error as FitCheckError {
            if case .modelNotFound(let id) = error {
                #expect(id == "nonexistent")
            } else {
                Issue.record("Wrong error case: \(error)")
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Hardware profile is cached after first call")
    func profileCaching() async throws {
        let fc = makeFitCheck()
        let first = try await fc.hardwareProfile()
        let second = try await fc.hardwareProfile()
        #expect(first == second)
    }

    @Test("models(family:) filters correctly")
    func filterByFamily() async throws {
        let models = [
            ModelCard.fixture(id: "llama", family: .llama),
            ModelCard.fixture(id: "phi", family: .phi),
        ]
        let fc = makeFitCheck(models: models)
        let result = try await fc.models(family: .llama)
        #expect(result.count == 1)
        #expect(result[0].family == .llama)
    }

    @Test("models(matching:) searches across fields")
    func search() async throws {
        let fc = makeFitCheck(models: [
            ModelCard.fixture(id: "llama-3.1-8b", name: "Llama 3.1"),
        ])
        let byName = try await fc.models(matching: "llama")
        #expect(byName.count == 1)

        let byID = try await fc.models(matching: "3.1-8b")
        #expect(byID.count == 1)

        let noMatch = try await fc.models(matching: "gpt")
        #expect(noMatch.isEmpty)
    }

    @Test("models(maxParameters:) filters by parameter count")
    func filterByParams() async throws {
        let models = [
            ModelCard.fixture(id: "small", parameterCount: ParameterCount(billions: 3)),
            ModelCard.fixture(id: "large", parameterCount: ParameterCount(billions: 70)),
        ]
        let fc = makeFitCheck(models: models)
        let result = try await fc.models(maxParameters: 10)
        #expect(result.count == 1)
        #expect(result[0].id == "small")
    }
}
