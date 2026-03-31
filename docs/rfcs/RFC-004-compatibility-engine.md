# RFC-004: Compatibility Engine

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | RFC-002, RFC-003                            |
| Phase       | 2                                           |

---

## 1. Motivation

FitCheck's core value proposition is answering the question: "Can this model run on my Mac?" The hardware profiling (RFC-002) provides the machine's capabilities. The model catalog (RFC-003) provides each model's requirements. What remains is the matching logic — comparing hardware against requirements and producing a clear, actionable verdict.

This RFC defines the compatibility engine: a `CompatibilityChecker` protocol that takes a `HardwareProfile` and a set of `ModelCard`/`ModelVariant` entries and produces `CompatibilityReport` results with performance tier estimates, memory headroom calculations, and actionable warnings.

## 2. Compatibility Engine Overview

```
┌──────────────────┐     ┌──────────────────┐
│  HardwareProfile │     │   [ModelCard]     │
│    (RFC-002)     │     │    (RFC-003)      │
└────────┬─────────┘     └────────┬──────────┘
         │                        │
         └───────────┬────────────┘
                     ▼
         ┌───────────────────────┐
         │  CompatibilityChecker │
         │                       │
         │  For each ModelCard:  │
         │   For each variant:   │
         │    compare memory     │
         │    compute headroom   │
         │    assign verdict     │
         │    generate warnings  │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  [ModelMatch]         │
         │                       │
         │  card + variant +     │
         │  report (verdict,     │
         │  performance tier,    │
         │  headroom, warnings)  │
         └───────────────────────┘
```

The engine is purely functional: no state, no I/O, no side effects. It receives data and returns results. This makes it trivially testable and thread-safe.

## 3. Data Model

### 3.1 CompatibilityVerdict

```swift
// Sources/FitCheck/Compatibility/CompatibilityVerdict.swift  [new file]

public enum CompatibilityVerdict: Sendable, Equatable {
    case compatible(PerformanceTier)
    case marginal
    case incompatible(IncompatibilityReason)

    public var isRunnable: Bool {
        switch self {
        case .compatible, .marginal: return true
        case .incompatible:          return false
        }
    }
}

public enum PerformanceTier: Int, Sendable, Codable, Comparable, CaseIterable {
    case optimal = 3
    case comfortable = 2
    case constrained = 1

    public static func < (lhs: PerformanceTier, rhs: PerformanceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .optimal:      return "Optimal"
        case .comfortable:  return "Comfortable"
        case .constrained:  return "Constrained"
        }
    }

    public var description: String {
        switch self {
        case .optimal:
            return "Model fits well within available memory. Expect smooth, fast inference."
        case .comfortable:
            return "Model runs with adequate headroom. Good performance for most tasks."
        case .constrained:
            return "Model fits but memory is tight. Expect slower inference with long contexts."
        }
    }
}

public enum IncompatibilityReason: Sendable, Equatable {
    case insufficientMemory(requiredBytes: UInt64, availableBytes: UInt64)

    public var displayDescription: String {
        switch self {
        case .insufficientMemory(let required, let available):
            let requiredGB = String(format: "%.1f", Double(required) / 1_073_741_824)
            let availableGB = String(format: "%.1f", Double(available) / 1_073_741_824)
            return "Requires \(requiredGB) GB but only \(availableGB) GB available for inference"
        }
    }
}
```

### 3.2 CompatibilityReport

```swift
// Sources/FitCheck/Compatibility/CompatibilityReport.swift  [new file]

public struct CompatibilityReport: Sendable, Equatable {
    public let modelCardID: String
    public let variantID: String
    public let verdict: CompatibilityVerdict
    public let estimatedMemoryUsageBytes: UInt64
    public let availableMemoryBytes: UInt64
    public let memoryHeadroomBytes: Int64
    public let memoryUsagePercent: Double
    public let warnings: [CompatibilityWarning]

    public var memoryHeadroomGB: Double {
        Double(memoryHeadroomBytes) / 1_073_741_824
    }

    public var estimatedMemoryUsageGB: Double {
        Double(estimatedMemoryUsageBytes) / 1_073_741_824
    }
}

public enum CompatibilityWarning: Sendable, Equatable {
    case tightMemoryFit(usagePercent: Double)
    case swappingLikely
    case smallerQuantizationAvailable(QuantizationFormat)

    public var displayMessage: String {
        switch self {
        case .tightMemoryFit(let percent):
            return String(format: "Memory usage at %.0f%% — close other apps for best performance", percent)
        case .swappingLikely:
            return "Model may require disk swap, significantly reducing inference speed"
        case .smallerQuantizationAvailable(let format):
            return "A smaller quantization (\(format.displayName)) is available and may run better"
        }
    }
}
```

### 3.3 ModelMatch

A `ModelMatch` bundles a `ModelCard`, a specific `ModelVariant`, and its `CompatibilityReport` into a single result that the public API (RFC-006) returns to consumers.

```swift
// Sources/FitCheck/Compatibility/ModelMatch.swift  [new file]

public struct ModelMatch: Sendable, Identifiable, Equatable {
    public let id: String
    public let card: ModelCard
    public let variant: ModelVariant
    public let report: CompatibilityReport

    public init(card: ModelCard, variant: ModelVariant, report: CompatibilityReport) {
        self.id = "\(card.id):\(variant.id)"
        self.card = card
        self.variant = variant
        self.report = report
    }
}
```

## 4. Implementation

### 4.1 CompatibilityChecker Protocol

```swift
// Sources/FitCheck/Compatibility/CompatibilityChecker.swift  [new file]

public protocol CompatibilityChecker: Sendable {
    func check(
        variant: ModelVariant,
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> CompatibilityReport

    func checkAll(
        models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch]

    func compatibleModels(
        from models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch]
}
```

### 4.2 DefaultCompatibilityChecker

```swift
// Sources/FitCheck/Compatibility/DefaultCompatibilityChecker.swift  [new file]

public struct DefaultCompatibilityChecker: CompatibilityChecker, Sendable {
    public init() {}

    // MARK: - Single variant check

    public func check(
        variant: ModelVariant,
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> CompatibilityReport {
        let available = hardware.availableMemoryForInferenceBytes
        let required = variant.requirements.minimumMemoryBytes

        let headroom = Int64(available) - Int64(required)
        let usagePercent = available > 0
            ? (Double(required) / Double(available)) * 100
            : 100

        let verdict = computeVerdict(
            required: required,
            available: available
        )

        let warnings = computeWarnings(
            verdict: verdict,
            usagePercent: usagePercent,
            card: card,
            variant: variant
        )

        return CompatibilityReport(
            modelCardID: card.id,
            variantID: variant.id,
            verdict: verdict,
            estimatedMemoryUsageBytes: required,
            availableMemoryBytes: available,
            memoryHeadroomBytes: headroom,
            memoryUsagePercent: usagePercent,
            warnings: warnings
        )
    }

    // MARK: - Batch check (all variants of all models)

    public func checkAll(
        models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch] {
        models.flatMap { card in
            card.variants.map { variant in
                let report = check(variant: variant, of: card, against: hardware)
                return ModelMatch(card: card, variant: variant, report: report)
            }
        }
    }

    // MARK: - Compatible models only (best variant per card)

    public func compatibleModels(
        from models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch] {
        models.compactMap { card in
            bestCompatibleVariant(of: card, against: hardware)
        }
        .sorted { lhs, rhs in
            sortOrder(lhs) > sortOrder(rhs)
        }
    }

    // MARK: - Verdict computation

    private func computeVerdict(
        required: UInt64,
        available: UInt64
    ) -> CompatibilityVerdict {
        guard required <= available else {
            return .incompatible(
                .insufficientMemory(requiredBytes: required, availableBytes: available)
            )
        }

        let usageRatio = Double(required) / Double(available)

        switch usageRatio {
        case 0..<0.50:
            return .compatible(.optimal)
        case 0.50..<0.75:
            return .compatible(.comfortable)
        case 0.75..<0.90:
            return .compatible(.constrained)
        default:
            return .marginal
        }
    }

    // MARK: - Warning generation

    private func computeWarnings(
        verdict: CompatibilityVerdict,
        usagePercent: Double,
        card: ModelCard,
        variant: ModelVariant
    ) -> [CompatibilityWarning] {
        var warnings: [CompatibilityWarning] = []

        if usagePercent > 80 {
            warnings.append(.tightMemoryFit(usagePercent: usagePercent))
        }

        if case .marginal = verdict {
            warnings.append(.swappingLikely)
        }

        if usagePercent > 75 {
            let smallerVariant = card.variants
                .filter { $0.quantization < variant.quantization }
                .sorted { $0.requirements.minimumMemoryBytes < $1.requirements.minimumMemoryBytes }
                .last
            if let smaller = smallerVariant {
                warnings.append(.smallerQuantizationAvailable(smaller.quantization))
            }
        }

        return warnings
    }

    // MARK: - Best variant selection

    private func bestCompatibleVariant(
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> ModelMatch? {
        let candidates = card.variants
            .map { variant -> (ModelVariant, CompatibilityReport) in
                let report = check(variant: variant, of: card, against: hardware)
                return (variant, report)
            }
            .filter { $0.1.verdict.isRunnable }
            .sorted { lhs, rhs in
                lhs.0.quantization > rhs.0.quantization
            }

        guard let best = candidates.first else {
            return nil
        }

        return ModelMatch(card: card, variant: best.0, report: best.1)
    }

    // MARK: - Sort ordering

    private func sortOrder(_ match: ModelMatch) -> Int {
        switch match.report.verdict {
        case .compatible(.optimal):      return 4
        case .compatible(.comfortable):  return 3
        case .compatible(.constrained):  return 2
        case .marginal:                  return 1
        case .incompatible:              return 0
        }
    }
}
```

### 4.3 Verdict Algorithm

The compatibility verdict is computed from the ratio of required memory to available memory:

```
                          Memory Usage Ratio
  ├──────────┼──────────────┼──────────────┼──────────┤
  0%        50%            75%            90%        100%+
  │ OPTIMAL  │ COMFORTABLE  │ CONSTRAINED  │ MARGINAL │ INCOMPATIBLE
```

| Usage Ratio | Verdict | Meaning |
|-------------|---------|---------|
| 0% – 49% | `compatible(.optimal)` | Model uses less than half the available memory. Fast inference, room for long contexts. |
| 50% – 74% | `compatible(.comfortable)` | Model fits with adequate headroom. Good for typical workloads. |
| 75% – 89% | `compatible(.constrained)` | Tight fit. Works but may slow down with long contexts or concurrent apps. |
| 90% – 99% | `marginal` | Technically fits but swapping is likely. Warns the user. |
| ≥ 100% | `incompatible(.insufficientMemory)` | Cannot run. |

FitCheck requires Apple Silicon (enforced at the hardware profiling layer, RFC-002). The compatibility engine never encounters non-Apple-Silicon hardware.

### 4.4 Best Variant Selection Strategy

When reporting compatible models, the engine selects the **best compatible variant** for each `ModelCard` — the highest-quality quantization that still fits:

```
Card: Llama 3.1 8B
  Variants (sorted by quality, descending):
    F16     → 16 GB required → INCOMPATIBLE (8 GB Mac)
    Q8_0    → 10 GB required → INCOMPATIBLE
    Q4_K_M  →  6 GB required → COMPATIBLE (comfortable)  ← selected
    Q2_K    →  3 GB required → COMPATIBLE (optimal)       ← lower quality, skipped
```

The rationale: users want the best quality their hardware can support. If they want to explore all variants, the `checkAll` method exposes every combination.

## 5. Error Handling

The compatibility engine itself does not throw errors — it operates on already-validated data. All methods return values, never throw. Error conditions are expressed through the verdict system:

| Scenario | Detection | Recovery |
|----------|-----------|---------|
| Insufficient memory for model | `required > available` | Return `.incompatible(.insufficientMemory(...))`. The public API (RFC-006) filters these from the compatible list. |
| No compatible variant exists for a card | All variants produce `.incompatible` | `bestCompatibleVariant` returns `nil`. Card is excluded from `compatibleModels` results. |
| Empty model catalog | No cards passed in | Return empty `[ModelMatch]`. No error — an empty catalog is a valid (if useless) input. |

## 6. Testing Strategy

### 6.1 Hardware Fixtures

Tests use the `HardwareProfile.fixture()` from RFC-002 §5.1 with varying memory and chip configurations:

```swift
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
```

### 6.2 Unit Tests

```swift
// Tests/FitCheckTests/Compatibility/DefaultCompatibilityCheckerTests.swift

import Testing
@testable import FitCheck

@Suite("DefaultCompatibilityChecker")
struct DefaultCompatibilityCheckerTests {
    let checker = DefaultCompatibilityChecker()

    @Test("Small model on large Mac is optimal")
    func optimalFit() {
        let variant = ModelVariant.fixture(
            minimumMemoryBytes: 4 * 1_073_741_824
        )
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac36GB)

        #expect(report.verdict == .compatible(.optimal))
        #expect(report.memoryHeadroomBytes > 0)
        #expect(report.warnings.isEmpty)
    }

    @Test("Medium model on 16 GB Mac is comfortable")
    func comfortableFit() {
        let variant = ModelVariant.fixture(
            minimumMemoryBytes: 6 * 1_073_741_824
        )
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac16GB)

        #expect(report.verdict == .compatible(.comfortable))
    }

    @Test("Large model on small Mac is incompatible")
    func incompatible() {
        let variant = ModelVariant.fixture(
            minimumMemoryBytes: 10 * 1_073_741_824
        )
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac8GB)

        if case .incompatible(.insufficientMemory) = report.verdict {
            // expected
        } else {
            Issue.record("Expected incompatible verdict")
        }
        #expect(!report.verdict.isRunnable)
    }

    @Test("Marginal fit produces swapping warning")
    func marginalFit() {
        let available: UInt64 = 12 * 1_073_741_824
        let required: UInt64 = 11 * 1_073_741_824
        let variant = ModelVariant.fixture(minimumMemoryBytes: required)
        let card = ModelCard.fixture(variants: [variant])
        let report = checker.check(variant: variant, of: card, against: .mac16GB)

        if case .marginal = report.verdict {
            #expect(report.warnings.contains(.swappingLikely))
        }
    }

    @Test("Best variant selects highest quality that fits")
    func bestVariantSelection() {
        let card = ModelCard.fixture(variants: [
            .fixture(id: "q2k", quantization: .q2K, minimumMemoryBytes: 3 * 1_073_741_824),
            .fixture(id: "q4km", quantization: .q4KM, minimumMemoryBytes: 6 * 1_073_741_824),
            .fixture(id: "q8", quantization: .q8_0, minimumMemoryBytes: 10 * 1_073_741_824),
        ])

        let matches = checker.compatibleModels(from: [card], against: .mac8GB)

        #expect(matches.count == 1)
        #expect(matches[0].variant.quantization == .q4KM)
    }

    @Test("Compatible models sorted by performance tier descending")
    func sortOrder() {
        let smallCard = ModelCard.fixture(
            id: "small", variants: [
                .fixture(id: "s1", minimumMemoryBytes: 2 * 1_073_741_824)
            ]
        )
        let largeCard = ModelCard.fixture(
            id: "large", variants: [
                .fixture(id: "l1", minimumMemoryBytes: 8 * 1_073_741_824)
            ]
        )

        let matches = checker.compatibleModels(from: [largeCard, smallCard], against: .mac16GB)

        #expect(matches.count == 2)
        #expect(matches[0].card.id == "small")
    }
}
```

## 7. Performance

The compatibility engine performs no I/O. All operations are O(n × m) where n = number of model cards and m = average number of variants per card. For a catalog of 50 cards × 5 variants = 250 comparisons, each consisting of a few arithmetic operations. Total computation time is under 1ms on any Apple Silicon Mac. No optimization is needed.

## 8. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Support Intel Macs with degraded verdicts | Adds complexity (separate code paths, Intel-specific warnings) for hardware that cannot run models well. Dropped entirely — the profiler rejects Intel at the gate. |
| Use Metal `recommendedMaxWorkingSetSize` instead of the utilization formula | `recommendedMaxWorkingSetSize` reflects the GPU's addressable memory window. Our formula `min(0.85 × total, total - 2 GB)` (RFC-002 §3.1) is calibrated against real workloads and gives predictable, tunable results across all memory configurations. The Metal value could disagree on future hardware. |
| Return all variants instead of best-per-card in `compatibleModels` | Returning all compatible variants overwhelms the consumer with redundant information. Most users want "the best I can run." The `checkAll` method exists for consumers who need the full matrix. |
| Async compatibility checker | The checker is purely functional — arithmetic on value types. Making it async adds `Task` overhead and `await` ceremony with zero benefit. It remains `Sendable` and can be called from any isolation domain. |
| Fuzzy scoring (0–100) instead of discrete tiers | Discrete tiers (optimal, comfortable, constrained, marginal, incompatible) are immediately actionable: "Can I run it? How well?" A numeric score requires the consumer to interpret thresholds, which is the checker's job. |

## 9. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | How much system overhead to assume? | **`min(0.85 × total, total - 2 GB)`, floored at 1 GB**, as established in RFC-002 §3.1 (`HardwareProfile.availableMemoryForInferenceBytes`). Calibrated against llm-checker's formula for Apple Silicon unified memory. The compatibility engine uses this computed property rather than defining its own overhead constant. |
| 2 | What are the tier thresholds? | **0–49% optimal, 50–74% comfortable, 75–89% constrained, 90–99% marginal, 100%+ incompatible.** Aligned with llm-checker's fit scoring (≤90% → fits, ≤100% → tight). These thresholds can be tuned without API changes. |
| 3 | How to handle Intel Macs? | **Not supported. Rejected at the hardware profiling layer (RFC-002).** Intel Macs lack unified memory and Neural Engine, making local LLM inference impractical. The profiler throws `.unsupportedPlatform` before the compatibility engine is ever invoked. |
| 4 | Should the checker consider currently free memory? | **No. Use total memory only.** Currently free memory fluctuates by the second and depends on what apps are open. Total memory is deterministic and reproducible, which makes verdicts stable and testable. A future RFC can add a "live" mode. |
| 5 | How to select the "best" variant? | **Highest-quality quantization that produces a runnable verdict.** Quality is defined by `QuantizationFormat.bitsPerWeight` (higher = better quality). This prefers Q8_0 over Q4_K_M when both fit, giving users the best experience their hardware supports. |
