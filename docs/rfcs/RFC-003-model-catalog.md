# RFC-003: Model Catalog & Data Model

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | RFC-001                                     |
| Phase       | 1                                           |

---

## 1. Motivation

FitCheck needs a structured representation of every open-weight AI model it knows about: name, parameter count, quantization variants, memory requirements, licensing, and download sources. Without a well-defined data model, the compatibility engine (RFC-004) cannot compute fit verdicts and the download providers (RFC-005) cannot map models to provider-specific identifiers.

This RFC defines the core data types (`ModelCard`, `ModelVariant`, `ModelFamily`, `QuantizationFormat`), the `CatalogProvider` protocol for fetching model data, and two concrete providers: a bundled JSON catalog that ships with the package, and a remote catalog for updates.

## 2. Catalog Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  CatalogProvider                     │
│                   (protocol)                         │
└───────┬─────────────────────────────┬───────────────┘
        │                             │
        ▼                             ▼
┌───────────────────┐   ┌───────────────────────────┐
│ BundledCatalog    │   │ RemoteCatalogProvider      │
│ Provider          │   │                           │
│                   │   │  URL ──▶ URLSession       │
│ Bundle.module     │   │          ──▶ JSON decode  │
│  ──▶ JSON decode  │   │          ──▶ [ModelCard]  │
│  ──▶ [ModelCard]  │   │                           │
└───────────────────┘   └───────────────────────────┘
        │                             │
        └──────────┬──────────────────┘
                   ▼
        ┌───────────────────┐
        │ CompositeCatalog  │
        │ Provider          │
        │                   │
        │ bundled ∪ remote  │
        │ (remote overrides │
        │  bundled by ID)   │
        └───────────────────┘
```

The `CompositeCatalogProvider` merges bundled and remote catalogs. Bundled data ensures FitCheck works offline. Remote data — hosted as a JSON file in the FitCheck GitHub repository — allows catalog updates without a new package release, so even old installations always see the latest models.

## 3. Data Model

### 3.1 ModelCard

A `ModelCard` represents one logical model (e.g., "Llama 3.1 8B") with all its quantization variants.

```swift
// Sources/FitCheck/Catalog/ModelCard.swift  [new file]

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

    public var displayName: String {
        "\(name) \(parameterCount.displayString)"
    }

    public var bestQuantizationVariant: ModelVariant? {
        variants
            .sorted { $0.quantization.bitsPerWeight > $1.quantization.bitsPerWeight }
            .first
    }

    public var smallestVariant: ModelVariant? {
        variants
            .sorted { $0.sizeBytes < $1.sizeBytes }
            .first
    }
}
```

### 3.2 ParameterCount

```swift
// Inside ModelCard.swift

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
```

### 3.3 ModelFamily

```swift
// Sources/FitCheck/Catalog/ModelFamily.swift  [new file]

public enum ModelFamily: String, Sendable, Codable, CaseIterable, Equatable {
    case llama
    case codeLlama = "code_llama"
    case mistral
    case mixtral
    case phi
    case gemma
    case qwen
    case deepseek
    case starcoder
    case falcon
    case yi
    case vicuna
    case commandR = "command_r"
    case olmo
    case internLM = "intern_lm"
    case smolLM = "smol_lm"
    case other

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ModelFamily(rawValue: rawValue) ?? .other
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .llama:        return "Llama"
        case .codeLlama:    return "Code Llama"
        case .mistral:      return "Mistral"
        case .mixtral:      return "Mixtral"
        case .phi:          return "Phi"
        case .gemma:        return "Gemma"
        case .qwen:         return "Qwen"
        case .deepseek:     return "DeepSeek"
        case .starcoder:    return "StarCoder"
        case .falcon:       return "Falcon"
        case .yi:           return "Yi"
        case .vicuna:       return "Vicuna"
        case .commandR:     return "Command R"
        case .olmo:         return "OLMo"
        case .internLM:     return "InternLM"
        case .smolLM:       return "SmolLM"
        case .other:        return "Other"
        }
    }
}
```

### 3.4 ModelVariant

A `ModelVariant` represents one specific downloadable artifact of a model — a particular quantization at a known file size.

```swift
// Sources/FitCheck/Catalog/ModelVariant.swift  [new file]

public struct ModelVariant: Sendable, Identifiable, Codable, Equatable {
    public let id: String
    public let quantization: QuantizationFormat
    public let sizeBytes: UInt64
    public let requirements: ModelRequirements
    public let ollamaTag: String?
    public let lmStudioModelID: String?
    public let downloadURL: URL?

    public var sizeGB: Double {
        Double(sizeBytes) / 1_073_741_824
    }

    public var sizeDisplayString: String {
        String(format: "%.1f GB", sizeGB)
    }
}
```

### 3.5 QuantizationFormat

```swift
// Sources/FitCheck/Catalog/QuantizationFormat.swift  [new file]

public enum QuantizationFormat: String, Sendable, Codable, CaseIterable, Equatable, Comparable {
    case q2K   = "Q2_K"
    case q3KS  = "Q3_K_S"
    case q3KM  = "Q3_K_M"
    case q4_0  = "Q4_0"
    case q4KS  = "Q4_K_S"
    case q4KM  = "Q4_K_M"
    case q5_0  = "Q5_0"
    case q5KS  = "Q5_K_S"
    case q5KM  = "Q5_K_M"
    case q6K   = "Q6_K"
    case q8_0  = "Q8_0"
    case f16   = "F16"
    case f32   = "F32"

    public var bitsPerWeight: Double {
        gbPerBillionParams * 8
    }

    public var gbPerBillionParams: Double {
        switch self {
        case .q2K:  return 0.37
        case .q3KS: return 0.44
        case .q3KM: return 0.48
        case .q4_0: return 0.54
        case .q4KS: return 0.56
        case .q4KM: return 0.58
        case .q5_0: return 0.63
        case .q5KS: return 0.66
        case .q5KM: return 0.68
        case .q6K:  return 0.80
        case .q8_0: return 1.05
        case .f16:  return 2.00
        case .f32:  return 4.00
        }
    }

    public var displayName: String {
        rawValue
    }

    public var qualityTier: QuantizationQuality {
        switch self {
        case .q2K, .q3KS, .q3KM:                    return .low
        case .q4_0, .q4KS, .q4KM:                   return .medium
        case .q5_0, .q5KS, .q5KM, .q6K:             return .high
        case .q8_0, .f16, .f32:                      return .nearLossless
        }
    }

    public static func < (lhs: QuantizationFormat, rhs: QuantizationFormat) -> Bool {
        lhs.bitsPerWeight < rhs.bitsPerWeight
    }
}

public enum QuantizationQuality: String, Sendable, Codable, Comparable {
    case low
    case medium
    case high
    case nearLossless = "near_lossless"

    public static func < (lhs: QuantizationQuality, rhs: QuantizationQuality) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    internal var sortOrder: Int {
        switch self {
        case .low:            return 0
        case .medium:         return 1
        case .high:           return 2
        case .nearLossless:   return 3
        }
    }
}
```

### 3.6 ModelRequirements

```swift
// Inside ModelVariant.swift

public struct ModelRequirements: Sendable, Codable, Equatable {
    public let minimumMemoryBytes: UInt64
    public let recommendedMemoryBytes: UInt64
    public let diskSizeBytes: UInt64

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
```

### 3.7 ModelLicense

```swift
// Sources/FitCheck/Catalog/ModelLicense.swift  [new file]

public struct ModelLicense: Sendable, Codable, Equatable {
    public let identifier: String
    public let name: String
    public let url: URL?
    public let isOpenSource: Bool
}
```

### 3.8 Memory Requirement Estimation

When catalog entries do not specify explicit memory requirements, FitCheck computes them from parameter count and quantization using values calibrated against real Ollama download sizes (aligned with [llm-checker](https://github.com/Pavelevich/llm-checker)'s validated formula):

```swift
extension ModelRequirements {
    public static let defaultContextLength: UInt64 = 4096
    public static let runtimeOverheadBytes: UInt64 = 500 * 1_048_576

    public static func estimated(
        parameterCount: ParameterCount,
        quantization: QuantizationFormat,
        diskSizeBytes: UInt64,
        contextLength: UInt64 = defaultContextLength
    ) -> ModelRequirements {
        let modelWeightsBytes = UInt64(
            parameterCount.billions * quantization.gbPerBillionParams * 1_073_741_824
        )

        let kvCacheBytes = UInt64(
            0.000008 * parameterCount.billions * Double(contextLength) * 1_073_741_824
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
```

**Formula breakdown:**
- `modelWeightsBytes = parameterCount × gbPerBillionParams` — calibrated against real Ollama GGUF sizes (includes structural metadata overhead beyond raw weight data)
- `kvCacheBytes = 0.000008 × paramsB × contextLength` (in GB) — KV cache scales with both model size and context window. For 7B @ 4096 tokens: ~0.23 GB. For 70B @ 4096: ~2.3 GB.
- `runtimeOverheadBytes = 500 MB` — inference runtime structures, scratch buffers
- `recommended = minimum × 1.2` — 20% headroom for comfortable operation

**Calibrated `gbPerBillionParams` values** (from llm-checker, validated against real Ollama sizes):

| Quantization | GB per billion params | Source |
|-------------|----------------------|--------|
| Q2_K | 0.37 | Calibrated |
| Q3_K_M | 0.48 | Calibrated |
| Q4_K_M | 0.58 | Calibrated |
| Q5_K_M | 0.68 | Calibrated |
| Q6_K | 0.80 | Calibrated |
| Q8_0 | 1.05 | Calibrated (includes GGUF structural overhead) |
| F16 | 2.00 | Theoretical |

**Examples:**

| Model | Quantization | Params | Weights | KV Cache (4K ctx) | + Runtime | Minimum | Recommended |
|-------|-------------|--------|---------|-------------------|-----------|---------|-------------|
| Phi-3 Mini | Q4_K_M | 3.8B | 2.2 GB | 0.12 GB | 0.5 GB | 2.8 GB | 3.4 GB |
| Mistral 7B | Q4_K_M | 7B | 4.1 GB | 0.23 GB | 0.5 GB | 4.8 GB | 5.7 GB |
| Llama 3.1 8B | Q4_K_M | 8B | 4.6 GB | 0.26 GB | 0.5 GB | 5.4 GB | 6.5 GB |
| Llama 3.1 70B | Q4_K_M | 70B | 40.6 GB | 2.29 GB | 0.5 GB | 43.4 GB | 52.1 GB |

## 4. Catalog Providers

### 4.1 CatalogProvider Protocol

```swift
// Sources/FitCheck/Catalog/CatalogProvider.swift  [new file]

public protocol CatalogProvider: Sendable {
    func fetchModels() async throws -> [ModelCard]
}
```

### 4.2 BundledCatalogProvider

Reads model data from a JSON file embedded in the Swift package bundle.

```swift
// Sources/FitCheck/Catalog/BundledCatalogProvider.swift  [new file]

import Foundation

public struct BundledCatalogProvider: CatalogProvider, Sendable {
    public init() {}

    public func fetchModels() async throws -> [ModelCard] {
        guard let url = Bundle.module.url(
            forResource: "bundled-catalog",
            withExtension: "json"
        ) else {
            throw FitCheckError.resourceMissing(name: "bundled-catalog.json")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FitCheckError.catalogLoadFailed(underlying: error)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let catalog = try decoder.decode(CatalogFile.self, from: data)
            return catalog.models
        } catch {
            throw FitCheckError.catalogDecodingFailed(
                path: url.path,
                underlying: error
            )
        }
    }
}

internal struct CatalogFile: Codable, Sendable {
    let version: String
    let generatedAt: String
    let models: [ModelCard]
}
```

### 4.3 RemoteCatalogProvider

Fetches an updated catalog from a remote URL. Defaults to the FitCheck GitHub repository's `data/catalog.json` file, ensuring even old package installations can discover newly released models. The URL is consumer-configurable for private catalogs or mirrors.

```swift
// Sources/FitCheck/Catalog/RemoteCatalogProvider.swift  [new file]

import Foundation

public struct RemoteCatalogProvider: CatalogProvider, Sendable {
    public static let defaultURL = URL(
        string: "https://raw.githubusercontent.com/nicklama/FitCheck/main/data/catalog.json"
    )!

    private let url: URL
    private let session: URLSession
    private let timeoutSeconds: TimeInterval

    public init(
        url: URL = Self.defaultURL,
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 10
    ) {
        self.url = url
        self.session = session
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetchModels() async throws -> [ModelCard] {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        request.cachePolicy = .reloadRevalidatingCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FitCheckError.networkUnavailable(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FitCheckError.catalogLoadFailed(
                underlying: URLError(.badServerResponse)
            )
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let catalog = try decoder.decode(CatalogFile.self, from: data)
            return catalog.models
        } catch {
            throw FitCheckError.catalogDecodingFailed(
                path: url.absoluteString,
                underlying: error
            )
        }
    }
}
```

### 4.4 CompositeCatalogProvider

Merges bundled and remote catalogs. Remote entries override bundled entries with the same `id`.

```swift
// Inside CatalogProvider.swift

public struct CompositeCatalogProvider: CatalogProvider, Sendable {
    private let primary: any CatalogProvider
    private let fallback: any CatalogProvider

    public init(primary: any CatalogProvider, fallback: any CatalogProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    public func fetchModels() async throws -> [ModelCard] {
        let fallbackModels = try await fallback.fetchModels()

        let primaryModels: [ModelCard]
        do {
            primaryModels = try await primary.fetchModels()
        } catch {
            Log.catalog.info("Primary catalog unavailable, using fallback only: \(error)")
            return fallbackModels
        }

        var modelsByID: [String: ModelCard] = [:]
        for model in fallbackModels {
            modelsByID[model.id] = model
        }
        for model in primaryModels {
            modelsByID[model.id] = model
        }

        return Array(modelsByID.values).sorted { $0.name < $1.name }
    }
}
```

## 5. Bundled Catalog Schema

The file `Sources/FitCheck/Resources/bundled-catalog.json` follows this schema:

```json
{
  "version": "1.0.0",
  "generated_at": "2026-03-31T00:00:00Z",
  "models": [
    {
      "id": "llama-3.1-8b",
      "name": "Llama 3.1",
      "family": "llama",
      "parameter_count": { "billions": 8 },
      "description": "Meta's general-purpose LLM, strong multilingual and reasoning capabilities.",
      "license": {
        "identifier": "llama-3.1",
        "name": "Llama 3.1 Community License",
        "url": "https://github.com/meta-llama/llama-models/blob/main/models/llama3_1/LICENSE",
        "is_open_source": true
      },
      "release_date": "2024-07-23",
      "source_url": "https://llama.meta.com",
      "hugging_face_url": "https://huggingface.co/meta-llama/Llama-3.1-8B",
      "variants": [
        {
          "id": "llama-3.1-8b-q4km",
          "quantization": "Q4_K_M",
          "size_bytes": 4920000000,
          "requirements": {
            "minimum_memory_bytes": 6600000000,
            "recommended_memory_bytes": 8250000000,
            "disk_size_bytes": 4920000000
          },
          "ollama_tag": "llama3.1:8b-instruct-q4_K_M",
          "lm_studio_model_id": "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF",
          "download_url": "https://huggingface.co/lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF"
        },
        {
          "id": "llama-3.1-8b-q8",
          "quantization": "Q8_0",
          "size_bytes": 8540000000,
          "requirements": {
            "minimum_memory_bytes": 10040000000,
            "recommended_memory_bytes": 12550000000,
            "disk_size_bytes": 8540000000
          },
          "ollama_tag": "llama3.1:8b-instruct-q8_0",
          "lm_studio_model_id": "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF",
          "download_url": "https://huggingface.co/lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF"
        }
      ]
    }
  ]
}
```

The bundled catalog ships with a comprehensive set of 100+ model cards covering all major open-weight model families (Llama, Mistral, Phi, Gemma, Qwen, DeepSeek, CodeLlama, Mixtral, Yi, Falcon, OLMo, SmolLM, etc.) across common quantization formats (Q4_K_M, Q5_K_M, Q8_0 at minimum). Each card includes 3–5 variants. The bundled catalog is a build-time snapshot; the remote catalog at `RemoteCatalogProvider.defaultURL` provides live updates.

### 5.1 GitHub-Hosted Remote Catalog

The canonical live catalog is maintained in the FitCheck repository at `data/catalog.json`. This file follows the same schema as the bundled catalog (§5) and is served via GitHub's raw content CDN.

```
┌───────────────────────────────────────────────────┐
│  FitCheck GitHub Repository                        │
│                                                    │
│  data/                                             │
│  └── catalog.json   ← maintained via PRs / CI     │
│                                                    │
│  Raw URL:                                          │
│  https://raw.githubusercontent.com/                │
│    nicklama/FitCheck/main/data/catalog.json        │
└───────────────────────────────────────────────────┘
         │
         ▼  (HTTP GET at runtime)
┌───────────────────────────────────────────────────┐
│  RemoteCatalogProvider                             │
│                                                    │
│  • Default URL: RemoteCatalogProvider.defaultURL   │
│  • Consumer can override with any URL              │
│  • 10-second timeout, graceful fallback            │
└───────────────────────────────────────────────────┘
```

**Update workflow:** To add a new model to the catalog, submit a PR to the FitCheck repository editing `data/catalog.json`. CI validates the JSON schema. Once merged, every FitCheck installation using the default remote URL immediately sees the new model on its next `allModels()` or `compatibleModels()` call.

**Consumer override:** Organizations can host their own catalog at a private URL and pass it to `RemoteCatalogProvider(url:)`. The schema is identical.

### 5.2 Schema Versioning

The `version` field uses semantic versioning:
- **Patch** (1.0.x): new models or variants added
- **Minor** (1.x.0): new fields added to existing types (backward compatible)
- **Major** (x.0.0): breaking schema changes (field renames, type changes)

The decoder ignores unknown keys, so minor version bumps in the remote catalog are backward compatible with older package versions.

## 6. Error Handling

| Scenario | Detection | Recovery |
|----------|-----------|---------|
| Bundled JSON file missing from bundle | `Bundle.module.url` returns `nil` | Throw `.resourceMissing(name:)`. This indicates a packaging error — the consumer must verify SPM integration. |
| Bundled JSON is corrupt or unparseable | `JSONDecoder.decode` throws | Throw `.catalogDecodingFailed(path:underlying:)`. Log the path and underlying error. |
| Remote URL unreachable (no network) | `URLSession.data(for:)` throws | Throw `.networkUnavailable(underlying:)`. `CompositeCatalogProvider` catches this and falls back to bundled data. |
| Remote returns non-2xx HTTP status | `HTTPURLResponse.statusCode` check | Throw `.catalogLoadFailed(underlying:)`. Fall back to bundled data. |
| Remote JSON has incompatible schema | `JSONDecoder.decode` throws | Throw `.catalogDecodingFailed(path:underlying:)`. Fall back to bundled data. |
| Model ID collision during merge | Duplicate `id` values | Remote entry overwrites bundled entry. Last-write-wins by design — remote data is authoritative. |

## 7. Testing Strategy

### 7.1 Mock Catalog Provider

```swift
// Tests/FitCheckTests/Catalog/MockCatalogProvider.swift

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
```

### 7.2 Test Fixtures

```swift
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
```

### 7.3 Unit Tests

```swift
// Tests/FitCheckTests/Catalog/ModelCardTests.swift

import Testing
@testable import FitCheck

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

@Suite("QuantizationFormat")
struct QuantizationFormatTests {
    @Test("GB per billion params follows calibrated values")
    func gbPerBillionParams() {
        #expect(QuantizationFormat.q4KM.gbPerBillionParams == 0.58)
        #expect(QuantizationFormat.q8_0.gbPerBillionParams == 1.05)
        #expect(QuantizationFormat.f16.gbPerBillionParams == 2.00)
    }

    @Test("Bits per weight is derived from GB per billion params")
    func bitsPerWeight() {
        #expect(QuantizationFormat.q4KM.bitsPerWeight == 0.58 * 8)
        #expect(QuantizationFormat.f16.bitsPerWeight == 16.0)
    }

    @Test("Ordering is by bits per weight")
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

@Suite("ModelRequirements estimation")
struct ModelRequirementsTests {
    @Test("Estimated requirements for 7B Q4_K_M model")
    func estimate7B() {
        let req = ModelRequirements.estimated(
            parameterCount: ParameterCount(billions: 7),
            quantization: .q4KM,
            diskSizeBytes: 4_200_000_000
        )
        #expect(req.minimumMemoryGB > 5.0)
        #expect(req.minimumMemoryGB < 7.0)
        #expect(req.recommendedMemoryGB > req.minimumMemoryGB)
    }
}

@Suite("CompositeCatalogProvider")
struct CompositeCatalogProviderTests {
    @Test("Remote entries override bundled entries with same ID")
    func remoteOverridesBundled() async throws {
        let bundled = MockCatalogProvider(models: [
            .fixture(id: "model-a", name: "Old Name")
        ])
        let remote = MockCatalogProvider(models: [
            .fixture(id: "model-a", name: "New Name")
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
}
```

## 8. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Core Data / SwiftData for catalog storage | Massive overhead for a read-mostly dataset of ~200 entries. JSON decode into structs is simpler, faster, and has no schema migration burden. |
| Fetch catalog from models.dev API directly | Coupling to a third-party API creates a runtime dependency and a point of failure. A bundled JSON file works offline. The remote catalog is hosted in the FitCheck GitHub repo, giving us full control. |
| One `ModelCard` per quantization (no variants array) | A 7B model with 5 quantizations would produce 5 separate cards. Grouping variants under one card matches how users think about models and simplifies the UI/API. |
| Store requirements as a formula instead of explicit values | Formulas hide complexity and produce surprising results for edge cases (MoE models, multi-modal models). Explicit values in the catalog are verifiable; the estimation formula (§3.8) is a fallback, not the default. |
| Use `Date` for `releaseDate` | JSON date encoding is fragile across locales and formats. A `String` in `"YYYY-MM-DD"` format is unambiguous, sortable, and avoids `DateFormatter` configuration issues. |

## 9. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | How to store model data? | **Bundled JSON file in the SPM resource bundle, with a GitHub-hosted remote catalog as default primary.** Bundled data works offline. Remote data (hosted at `data/catalog.json` in the FitCheck GitHub repo) ensures even old installations see the latest models. `CompositeCatalogProvider` merges both, with remote taking precedence. |
| 2 | Should the catalog be mutable? | **No. The catalog is read-only at runtime.** `ModelCard` and `ModelVariant` are immutable value types. Catalog updates come from fetching a new JSON, not mutating existing entries. |
| 3 | How to compute memory requirements? | **Explicit values in the catalog, with a calibrated estimation formula as fallback.** The formula `params × gbPerBillionParams + KV cache + runtime overhead` (§3.8) uses values validated against real Ollama sizes, aligned with llm-checker. |
| 4 | What JSON decoding strategy? | **`convertFromSnakeCase` key decoding.** The JSON uses `snake_case` (standard for JSON), Swift types use `camelCase`. The strategy handles conversion automatically without `CodingKeys`. |
| 5 | How to handle new model families? | **The `ModelFamily` enum includes an `.other` case.** Unknown families in JSON decode to `.other` rather than causing a decoding failure. The enum is extended when new families gain significant adoption. |
| 6 | How to handle catalog versioning? | **Semantic version string in the catalog file.** Patch = new models, minor = new fields (backward compatible), major = breaking changes. The decoder ignores unknown keys for forward compatibility. |
