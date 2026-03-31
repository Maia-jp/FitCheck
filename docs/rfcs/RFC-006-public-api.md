# RFC-006: Public API Surface & Developer Experience

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | RFC-004, RFC-005                            |
| Phase       | 3                                           |

---

## 1. Motivation

RFC-001 through RFC-005 define FitCheck's internals: hardware profiling, model catalog, compatibility engine, and download providers. What remains is the public surface that consumers actually import and call. A poorly designed API would leak internal abstractions, require multi-step ceremonies for simple questions, or force consumers to understand subsystem wiring they should never see.

This RFC defines the `FitCheck` actor — a single entry point that composes all subsystems and exposes a clean, discoverable, batteries-included API. A Swift developer should be able to answer "What models can I run?" in three lines of code.

## 2. API Design Overview

```
┌───────────────────────────────────────────────────────────┐
│                      Consumer Code                         │
│                                                            │
│   let fc = FitCheck()                                      │
│   let matches = try await fc.compatibleModels()            │
│   for match in matches {                                   │
│       print(match.card.name, match.report.verdict)         │
│       for action in match.downloadActions {                │
│           print(action.displayInstructions)                │
│       }                                                    │
│   }                                                        │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│                       FitCheck (actor)                      │
│                                                             │
│  ┌───────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Hardware      │ │ Catalog      │ │ Compatibility    │  │
│  │ Profiler      │ │ Provider     │ │ Checker          │  │
│  │ (RFC-002)     │ │ (RFC-003)    │ │ (RFC-004)        │  │
│  └───────┬───────┘ └──────┬───────┘ └────────┬─────────┘  │
│          │                │                   │            │
│  ┌───────┴────────────────┴───────────────────┴─────────┐ │
│  │                 Cached State                          │ │
│  │  hardwareProfile: HardwareProfile?                    │ │
│  │  catalog: [ModelCard]?                                │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Download Providers (RFC-005)              │  │
│  │  [OllamaProvider, LMStudioProvider]                   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 Design Principles

1. **One import, one type.** `import FitCheck` gives access to everything. The `FitCheck` actor is the only type consumers need to instantiate.

2. **Batteries included, customization available.** Default initializer wires up all subsystems with production implementations. Consumers who need control (testing, custom catalogs) inject alternatives.

3. **Progressive disclosure.** Simple use cases require one method call (`compatibleModels()`). Advanced use cases (filtering, per-variant checks, provider detection) are available but not forced.

4. **No ceremony.** No configuration files, no setup steps, no registration. Instantiate and call.

## 3. FitCheck Actor

```swift
// Sources/FitCheck/FitCheck.swift  [existing file, replace contents]

import Foundation
import OSLog

public actor FitCheck {
    private let hardwareProfiler: any HardwareProfiler
    private let catalogProvider: any CatalogProvider
    private let compatibilityChecker: any CompatibilityChecker
    private let downloadProviders: [any DownloadProvider]

    private var cachedProfile: HardwareProfile?
    private var cachedCatalog: [ModelCard]?

    public init(
        hardwareProfiler: any HardwareProfiler = SystemHardwareProfiler(),
        catalogProvider: any CatalogProvider = CompositeCatalogProvider(
            primary: RemoteCatalogProvider(),
            fallback: BundledCatalogProvider()
        ),
        compatibilityChecker: any CompatibilityChecker = DefaultCompatibilityChecker(),
        downloadProviders: [any DownloadProvider] = [
            OllamaProvider(),
            LMStudioProvider(),
        ]
    ) {
        self.hardwareProfiler = hardwareProfiler
        self.catalogProvider = catalogProvider
        self.compatibilityChecker = compatibilityChecker
        self.downloadProviders = downloadProviders
    }

    // MARK: - Hardware

    public func hardwareProfile() throws -> HardwareProfile {
        if let cached = cachedProfile { return cached }
        let profile = try hardwareProfiler.profile()
        cachedProfile = profile
        Log.api.debug("Hardware profile loaded: \(profile.chip), \(profile.totalMemoryGB) GB")
        return profile
    }

    // MARK: - Catalog

    public func allModels() async throws -> [ModelCard] {
        if let cached = cachedCatalog { return cached }
        let models = try await catalogProvider.fetchModels()
        cachedCatalog = models
        Log.api.debug("Catalog loaded: \(models.count) models")
        return models
    }

    public func model(id: String) async throws -> ModelCard {
        let models = try await allModels()
        guard let card = models.first(where: { $0.id == id }) else {
            throw FitCheckError.modelNotFound(identifier: id)
        }
        return card
    }

    // MARK: - Compatibility

    public func compatibleModels() async throws -> [CompatibleModel] {
        let profile = try hardwareProfile()
        let models = try await allModels()
        let matches = compatibilityChecker.compatibleModels(from: models, against: profile)
        return matches.map { match in
            let actions = downloadActions(for: match.variant, of: match.card)
            return CompatibleModel(match: match, downloadActions: actions)
        }
    }

    public func allModelsWithCompatibility() async throws -> [CompatibleModel] {
        let profile = try hardwareProfile()
        let models = try await allModels()
        let matches = compatibilityChecker.checkAll(models: models, against: profile)
        return matches.map { match in
            let actions = downloadActions(for: match.variant, of: match.card)
            return CompatibleModel(match: match, downloadActions: actions)
        }
    }

    public func check(modelID: String) async throws -> [VariantReport] {
        let card = try await model(id: modelID)
        let profile = try hardwareProfile()
        return card.variants.map { variant in
            let report = compatibilityChecker.check(
                variant: variant, of: card, against: profile
            )
            let actions = downloadActions(for: variant, of: card)
            return VariantReport(
                variant: variant,
                report: report,
                downloadActions: actions
            )
        }
    }

    // MARK: - Download Providers

    public func providers() async throws -> [ProviderInfo] {
        var results: [ProviderInfo] = []
        for provider in downloadProviders {
            let installation = try await provider.detectInstallation()
            let installed = try await provider.installedModels()
            results.append(ProviderInfo(
                name: provider.name,
                type: provider.providerType,
                installation: installation,
                installationURL: provider.installationURL,
                installedModelCount: installed.count,
                installedModels: installed
            ))
        }
        return results
    }

    public func installedModels() async throws -> [InstalledModel] {
        var all: [InstalledModel] = []
        for provider in downloadProviders {
            let models = try await provider.installedModels()
            all.append(contentsOf: models)
        }
        return all
    }

    // MARK: - Filtering

    public func models(family: ModelFamily) async throws -> [ModelCard] {
        try await allModels().filter { $0.family == family }
    }

    public func models(maxParameters: Double) async throws -> [ModelCard] {
        try await allModels().filter { $0.parameterCount.billions <= maxParameters }
    }

    public func models(matching query: String) async throws -> [ModelCard] {
        let lowered = query.lowercased()
        return try await allModels().filter { card in
            card.name.lowercased().contains(lowered)
                || card.family.displayName.lowercased().contains(lowered)
                || card.description.lowercased().contains(lowered)
                || card.id.lowercased().contains(lowered)
        }
    }

    // MARK: - Cache Management

    public func refreshCatalog() async throws {
        cachedCatalog = nil
        _ = try await allModels()
    }

    public func invalidateHardwareCache() {
        cachedProfile = nil
    }

    // MARK: - Private Helpers

    private func downloadActions(
        for variant: ModelVariant,
        of card: ModelCard
    ) -> [DownloadAction] {
        downloadProviders.compactMap { provider in
            provider.downloadAction(for: variant, of: card)
        }
    }
}
```

## 4. Result Types

### 4.1 CompatibleModel

Enriches a `ModelMatch` (from RFC-004) with download actions. This is the primary result type returned to consumers.

```swift
// Inside FitCheck.swift

public struct CompatibleModel: Sendable, Identifiable {
    public let id: String
    public let card: ModelCard
    public let variant: ModelVariant
    public let report: CompatibilityReport
    public let downloadActions: [DownloadAction]

    internal init(match: ModelMatch, downloadActions: [DownloadAction]) {
        self.id = match.id
        self.card = match.card
        self.variant = match.variant
        self.report = match.report
        self.downloadActions = downloadActions
    }

    public var isRunnable: Bool {
        report.verdict.isRunnable
    }

    public var ollamaAction: DownloadAction? {
        downloadActions.first { $0.providerType == .ollama }
    }

    public var lmStudioAction: DownloadAction? {
        downloadActions.first { $0.providerType == .lmStudio }
    }
}
```

### 4.2 VariantReport

Returned by `check(modelID:)` for per-variant inspection of a single model.

```swift
// Inside FitCheck.swift

public struct VariantReport: Sendable {
    public let variant: ModelVariant
    public let report: CompatibilityReport
    public let downloadActions: [DownloadAction]

    public var isRunnable: Bool {
        report.verdict.isRunnable
    }
}
```

### 4.3 ProviderInfo

```swift
// Inside FitCheck.swift

public struct ProviderInfo: Sendable {
    public let name: String
    public let type: DownloadProviderType
    public let installation: ProviderInstallation
    public let installationURL: URL
    public let installedModelCount: Int
    public let installedModels: [InstalledModel]
}
```

## 5. Usage Examples

### 5.1 List Compatible Models

```swift
import FitCheck

let fc = FitCheck()
let models = try await fc.compatibleModels()

for model in models {
    print("\(model.card.displayName) — \(model.variant.quantization.displayName)")
    print("  Verdict: \(model.report.verdict)")
    print("  Memory: \(model.report.estimatedMemoryUsageGB) GB")

    if let ollama = model.ollamaAction {
        print("  Ollama: \(ollama.displayInstructions)")
    }
    if let lms = model.lmStudioAction {
        print("  LM Studio: \(lms.displayInstructions)")
    }
    print()
}
```

**Expected output on an M2 MacBook Air (16 GB):**
```
Phi-3 Mini 3.8B — Q4_K_M
  Verdict: compatible(optimal)
  Memory: 2.8 GB
  Ollama: ollama pull phi3:3.8b-mini-instruct-4k-q4_K_M
  LM Studio: lms get microsoft/Phi-3-mini-4k-instruct-GGUF

Mistral 7B — Q4_K_M
  Verdict: compatible(optimal)
  Memory: 4.8 GB
  Ollama: ollama pull mistral:7b-instruct-q4_K_M
  LM Studio: lms get TheBloke/Mistral-7B-Instruct-v0.2-GGUF

Llama 3.1 8B — Q4_K_M
  Verdict: compatible(optimal)
  Memory: 5.4 GB
  Ollama: ollama pull llama3.1:8b-instruct-q4_K_M
  LM Studio: lms get lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF
```

### 5.2 Check a Specific Model

```swift
let reports = try await fc.check(modelID: "llama-3.1-8b")

for report in reports {
    let emoji = report.isRunnable ? "✅" : "❌"
    print("\(emoji) \(report.variant.quantization.displayName): \(report.report.verdict)")
    for warning in report.report.warnings {
        print("  ⚠ \(warning.displayMessage)")
    }
}
```

### 5.3 Search Models

```swift
let deepseekModels = try await fc.models(matching: "deepseek")
let smallModels = try await fc.models(maxParameters: 8)
let llamaModels = try await fc.models(family: .llama)
```

### 5.4 Check Provider Status

```swift
let providerInfo = try await fc.providers()

for info in providerInfo {
    if info.installation.isInstalled {
        print("\(info.name) v\(info.installation.version ?? "?")")
        print("  \(info.installedModelCount) models installed")
    } else {
        print("\(info.name) — not installed")
        print("  Install: \(info.installationURL)")
    }
}
```

### 5.5 Custom Configuration

By default, `FitCheck()` uses the GitHub-hosted remote catalog (defined in RFC-003 §5.1) with the bundled catalog as fallback. To point at a private catalog:

```swift
let privateCatalog = RemoteCatalogProvider(
    url: URL(string: "https://my-company.com/fitcheck-catalog.json")!
)
let catalog = CompositeCatalogProvider(
    primary: privateCatalog,
    fallback: BundledCatalogProvider()
)

let fc = FitCheck(catalogProvider: catalog)
```

For fully offline use (no remote fetch at all):

```swift
let fc = FitCheck(catalogProvider: BundledCatalogProvider())
```

### 5.6 Hardware Profile Inspection

```swift
let profile = try await fc.hardwareProfile()
print("Chip: \(profile.chip)")
print("Memory: \(profile.totalMemoryGB) GB total")
print("Available for inference: \(Double(profile.availableMemoryForInferenceBytes) / 1_073_741_824) GB")
print("GPU cores: \(profile.gpuCoreCount)")
print("Neural Engine: \(profile.neuralEngineCoreCount) cores")
```

## 6. Error Handling

All errors thrown by the public API are `FitCheckError` cases (defined in RFC-001 §4):

| Method | Possible Errors | Consumer Action |
|--------|----------------|----------------|
| `hardwareProfile()` | `.hardwareDetectionFailed` | Display diagnostic, suggest filing a bug with the error's `reason` string. |
| `allModels()` | `.resourceMissing`, `.catalogLoadFailed`, `.catalogDecodingFailed` | Default uses `CompositeCatalogProvider` — remote failures are caught internally and fall back to bundled data. Only throws if the bundled catalog itself is broken (packaging error). |
| `model(id:)` | `.modelNotFound` | Verify model ID against `allModels()`. |
| `compatibleModels()` | Any from `hardwareProfile()` + `allModels()` | Handle each case. Both must succeed for compatibility checking. |
| `check(modelID:)` | Any from `model(id:)` + `hardwareProfile()` | Handle model-not-found or hardware detection failure. |
| `providers()` | None (individual provider failures are caught internally) | Always succeeds. Check `installation.status` per provider. |
| `installedModels()` | None (individual provider failures are caught internally) | Always succeeds. May return empty list. |

## 7. Testing Strategy

### 7.1 Integration Tests

```swift
// Tests/FitCheckTests/FitCheckTests.swift

import Testing
@testable import FitCheck

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
            variants: [.fixture(id: "s", minimumMemoryBytes: 4 * 1_073_741_824)]
        )
        let hugeModel = ModelCard.fixture(
            id: "huge",
            variants: [.fixture(id: "h", minimumMemoryBytes: 100 * 1_073_741_824)]
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

    @Test("refreshCatalog clears cache")
    func catalogRefresh() async throws {
        let fc = makeFitCheck(models: [.fixture()])
        let before = try await fc.allModels()
        try await fc.refreshCatalog()
        let after = try await fc.allModels()
        #expect(before.count == after.count)
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
}
```

## 8. API Summary

| Method | Returns | Description |
|--------|---------|-------------|
| `hardwareProfile()` | `HardwareProfile` | Current machine's hardware capabilities |
| `allModels()` | `[ModelCard]` | Every model in the catalog |
| `model(id:)` | `ModelCard` | Single model by identifier |
| `compatibleModels()` | `[CompatibleModel]` | Models that can run on this machine (best variant per card) |
| `allModelsWithCompatibility()` | `[CompatibleModel]` | Every variant of every model with compatibility verdicts |
| `check(modelID:)` | `[VariantReport]` | All variants of one model with verdicts and download actions |
| `providers()` | `[ProviderInfo]` | Status of all download providers |
| `installedModels()` | `[InstalledModel]` | Models already downloaded across all providers |
| `models(family:)` | `[ModelCard]` | Filter catalog by model family |
| `models(maxParameters:)` | `[ModelCard]` | Filter catalog by parameter count ceiling |
| `models(matching:)` | `[ModelCard]` | Search catalog by text query |
| `refreshCatalog()` | `Void` | Clear catalog cache and re-fetch |
| `invalidateHardwareCache()` | `Void` | Clear hardware profile cache |

## 9. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Struct with static methods instead of actor | Static methods preclude injection (no way to swap subsystems for testing or customization). An actor provides both injection via init and data-race safety via isolation. |
| Separate facade types per concern (HardwareInspector, ModelBrowser, DownloadManager) | Violates the "one type to import" principle. Consumers would need to learn three APIs and wire them together. The `FitCheck` actor composes internally and exposes a unified surface. |
| Return `AsyncStream<CompatibleModel>` instead of arrays | The catalog is finite (~50–200 models) and checked in <1ms. Streaming adds complexity without benefit. Arrays are simpler to consume, sort, filter, and display. |
| Combine publishers for reactivity | RFC-001 §7.2 establishes "no Combine" — the API uses `async`/`await` exclusively. Consumers who need reactivity can wrap calls in their own reactive layer. |
| Throw errors from `providers()` and `installedModels()` | Provider detection failures (binary not found, parse error) are expected states, not exceptional conditions. These methods catch errors internally and return degraded results. Throwing would force consumers to handle errors for every provider individually. |
| Global singleton `FitCheck.shared` | Singletons are hostile to testing. Consumers create their own `FitCheck()` instance and own its lifecycle. Multiple instances are safe — the actor isolates state. |

## 10. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Should `FitCheck` be a class, struct, or actor? | **Actor.** It holds mutable cached state (`cachedProfile`, `cachedCatalog`). An actor provides compile-time data-race safety under Swift 6 strict concurrency. Callers `await` all methods naturally. |
| 2 | Should there be a `FitCheck.shared` singleton? | **No.** Consumers create instances. Multiple instances with different configurations (custom catalogs, mock profilers) can coexist. Singletons prevent this. |
| 3 | What is the primary return type for compatible models? | **`CompatibleModel`** — a struct combining `ModelCard`, `ModelVariant`, `CompatibilityReport`, and `[DownloadAction]`. One type carries everything the consumer needs: what the model is, whether it fits, and how to get it. |
| 4 | Should download actions be eager or lazy? | **Eager.** Download actions are computed when `compatibleModels()` is called, not deferred. The computation is trivial (string formatting), and eager evaluation means the result is complete and ready to display. |
| 5 | Should catalog and hardware profile be loaded eagerly on init? | **No. Lazy on first access.** Loading the catalog involves file I/O (bundled) and network (remote). Hardware profiling involves syscalls. Deferring these to first use means `FitCheck()` construction is instant and side-effect-free. |
| 6 | How to handle filtering? | **Dedicated methods: `models(family:)`, `models(maxParameters:)`, `models(matching:)`.** Named methods are more discoverable than a generic `models(where:)` predicate. Consumers can also filter the arrays returned by `allModels()` with standard Swift collection methods. |
| 7 | What is the default catalog provider? | **`CompositeCatalogProvider(primary: RemoteCatalogProvider(), fallback: BundledCatalogProvider())`.** Remote-first ensures the latest models are always available. Bundled fallback ensures offline functionality. The remote URL defaults to the FitCheck GitHub repo (RFC-003 §5.1) but is consumer-configurable. |
