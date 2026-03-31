import Foundation
import Testing
@testable import FitCheck

// MARK: - Hardware fixtures for compatibility testing

extension HardwareProfile {
    static let mac8GB = HardwareProfile.fixture(
        chip: .appleSilicon(.m1),
        totalMemoryBytes: 8 * 1_073_741_824
    )
    static let mac16GB = HardwareProfile.fixture(
        chip: .appleSilicon(.m2),
        totalMemoryBytes: 16 * 1_073_741_824
    )
    static let mac36GB = HardwareProfile.fixture(
        chip: .appleSilicon(.m3Pro),
        totalMemoryBytes: 36 * 1_073_741_824
    )
    static let mac96GB = HardwareProfile.fixture(
        chip: .appleSilicon(.m2Max),
        totalMemoryBytes: 96 * 1_073_741_824
    )
}

// MARK: - DefaultCompatibilityChecker tests

@Suite("DefaultCompatibilityChecker")
struct DefaultCompatibilityCheckerTests {
    let checker = DefaultCompatibilityChecker()

    @Test("Small model on large Mac is optimal")
    func optimalFit() {
        let variant = ModelVariant.fixture(minimumMemoryBytes: 4 * 1_073_741_824)
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac36GB)

        #expect(report.verdict == .compatible(.optimal))
        #expect(report.memoryHeadroomBytes > 0)
        #expect(report.warnings.isEmpty)
    }

    @Test("Model using ~55% of available memory is comfortable")
    func comfortableFit() {
        let available = HardwareProfile.mac16GB.availableMemoryForInferenceBytes
        let required = UInt64(Double(available) * 0.55)
        let variant = ModelVariant.fixture(minimumMemoryBytes: required)
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac16GB)

        #expect(report.verdict == .compatible(.comfortable))
    }

    @Test("Large model on small Mac is incompatible")
    func incompatible() {
        let variant = ModelVariant.fixture(minimumMemoryBytes: 10 * 1_073_741_824)
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac8GB)

        if case .incompatible(.insufficientMemory) = report.verdict {} else {
            Issue.record("Expected incompatible verdict, got \(report.verdict)")
        }
        #expect(!report.verdict.isRunnable)
    }

    @Test("Marginal fit produces swapping warning")
    func marginalFitWarning() {
        let available = HardwareProfile.mac16GB.availableMemoryForInferenceBytes
        let required = UInt64(Double(available) * 0.95)
        let variant = ModelVariant.fixture(minimumMemoryBytes: required)
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac16GB)

        if case .marginal = report.verdict {
            #expect(report.warnings.contains(.swappingLikely))
        } else {
            Issue.record("Expected marginal verdict")
        }
    }

    @Test("Best variant selects highest quality that fits")
    func bestVariantSelection() {
        let card = ModelCard.fixture(variants: [
            .fixture(id: "q2k", quantization: .q2K, minimumMemoryBytes: 3 * 1_073_741_824 as UInt64),
            .fixture(id: "q4km", quantization: .q4KM, minimumMemoryBytes: 5 * 1_073_741_824 as UInt64),
            .fixture(id: "q8", quantization: .q8_0, minimumMemoryBytes: 10 * 1_073_741_824 as UInt64),
        ])

        let matches = checker.compatibleModels(from: [card], against: .mac8GB)

        #expect(matches.count == 1)
        #expect(matches[0].variant.quantization == QuantizationFormat.q4KM)
    }

    @Test("Compatible models sorted by performance tier descending")
    func sortOrder() {
        let smallCard = ModelCard.fixture(
            id: "small", variants: [.fixture(id: "s1", minimumMemoryBytes: 2 * 1_073_741_824 as UInt64)]
        )
        let largeCard = ModelCard.fixture(
            id: "large", variants: [.fixture(id: "l1", minimumMemoryBytes: 8 * 1_073_741_824 as UInt64)]
        )

        let matches = checker.compatibleModels(from: [largeCard, smallCard], against: .mac16GB)
        #expect(matches.count == 2)
        #expect(matches[0].card.id == "small")
    }

    @Test("checkAll returns all variant combinations")
    func checkAllVariants() {
        let card = ModelCard.fixture(variants: [
            .fixture(id: "v1", quantization: .q4KM),
            .fixture(id: "v2", quantization: .q8_0),
        ])

        let results = checker.checkAll(models: [card], against: .mac16GB)
        #expect(results.count == 2)
    }

    @Test("Empty catalog produces empty results")
    func emptyCatalog() {
        let results = checker.compatibleModels(from: [], against: .mac16GB)
        #expect(results.isEmpty)
    }
}
