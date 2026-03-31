# RFC-007: Catalog Generation Pipeline

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | RFC-003                                     |
| Phase       | 1                                           |

---

## 1. Motivation

The FitCheck model catalog (RFC-003) defines a schema for model cards, variants, and requirements. But a schema without data is useless. The catalog must contain 100+ model cards covering every major open-weight model family, each with multiple quantization variants, accurate memory requirements, Ollama tags, LM Studio identifiers, and download URLs.

Maintaining a model index by hand is unsustainable — new models release weekly. **models.dev** (by SST/anomalyco) already maintains an open-source, community-curated database of AI models at `https://models.dev/api.json`. Every model entry includes an `open_weights` boolean. This gives FitCheck a continuously updated index of open-weight models for free.

What models.dev does NOT have is local inference data: GGUF file sizes, quantization variants, Ollama tags, LM Studio identifiers, or memory requirements. FitCheck's generator layers this local-specific data on top.

This RFC defines a **Swift executable target** (`CatalogGenerator`) that fetches models.dev, cross-references with Ollama and HuggingFace APIs, computes memory requirements, validates output against the RFC-003 schema, and writes the catalog JSON. It lives in the same `Package.swift`, shares the same toolchain, and runs with `swift run CatalogGenerator`.

## 2. Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│              swift run CatalogGenerator                           │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Layer 0: models.dev                                       │  │
│  │                                                            │  │
│  │  GET https://models.dev/api.json                           │  │
│  │   ──▶ filter: open_weights == true                         │  │
│  │   ──▶ extract: name, family, release_date                  │  │
│  └────────────────────────┬───────────────────────────────────┘  │
│                           ▼                                       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Layer 1: Model Map (data/model-map.json)                  │  │
│  │                                                            │  │
│  │   models.dev ID → ollama name + HuggingFace GGUF repo      │  │
│  │   only mapped models are included in the catalog            │  │
│  └────────────────────────┬───────────────────────────────────┘  │
│                           ▼                                       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Layer 2: API Enrichment                                   │  │
│  │                                                            │  │
│  │  Ollama Registry ──▶ tags, sizes, quantizations            │  │
│  │  HuggingFace API ──▶ GGUF file sizes, LM Studio IDs       │  │
│  └────────────────────────┬───────────────────────────────────┘  │
│                           ▼                                       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Layer 3: Computation + Overrides + Validation              │  │
│  │                                                            │  │
│  │  Memory requirements = params × bits/weight + overhead     │  │
│  │  data/overrides.json → deep merge corrections              │  │
│  │  Decode through CatalogFile → if it decodes, schema valid  │  │
│  │                                                            │  │
│  │  ──▶ data/catalog.json                                     │  │
│  │  ──▶ Sources/FitCheck/Resources/bundled-catalog.json       │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## 3. Package Integration

### 3.1 Package.swift Changes

The generator is a separate executable target in the same package. It uses only `Foundation` — no dependency on the `FitCheck` library target (which requires Metal on macOS). This allows the generator to run on both macOS and Linux CI runners.

```swift
// Addition to Package.swift (RFC-001 §3)

.executableTarget(
    name: "CatalogGenerator",
    path: "Sources/CatalogGenerator"
),
```

No external dependencies. `Foundation` provides `URLSession`, `JSONDecoder`, `JSONEncoder`, `FileManager` — everything the generator needs.

### 3.2 Source Layout

```
Sources/CatalogGenerator/
├── CatalogGenerator.swift         # @main entry point, CLI argument parsing
├── Pipeline/
│   ├── ModelsDevClient.swift      # Fetch + parse models.dev/api.json
│   ├── OllamaRegistryClient.swift # Fetch Ollama tag/manifest data
│   ├── HuggingFaceClient.swift    # Fetch HuggingFace GGUF metadata
│   ├── ModelMapLoader.swift       # Load data/model-map.json
│   ├── VariantMerger.swift        # Merge Ollama + HF variant data
│   └── RequirementsCalculator.swift # Memory requirement formula
├── Validation/
│   └── CatalogValidator.swift     # Decode-based validation + sanity checks
└── Types/
    ├── CatalogOutput.swift        # Output types matching RFC-003 schema
    ├── ModelsDevTypes.swift       # Decodable types for models.dev API
    └── ModelMapEntry.swift        # Model map JSON types
```

### 3.3 Running

```bash
# Full generation
swift run CatalogGenerator

# Dry run (validate but don't write)
swift run CatalogGenerator --dry-run

# Single model (for testing)
swift run CatalogGenerator --model "meta/llama-3.1-8b-instruct"

# Show unmapped open-weight models from models.dev
swift run CatalogGenerator --discover

# Offline mode (skip API enrichment, use formula for sizes)
swift run CatalogGenerator --offline

# Verbose logging
swift run CatalogGenerator --verbose
```

## 4. Data Sources

### 4.1 Layer 0: models.dev

**What it is:** An open-source, community-maintained database of AI models. Free JSON API at `https://models.dev/api.json`. No authentication. MIT licensed.

**What FitCheck uses from it:**

| Field | Maps to |
|-------|---------|
| `name` | `ModelCard.name` |
| `family` | `ModelCard.family` → `ModelFamily` |
| `release_date` | `ModelCard.releaseDate` |
| `open_weights` | Filter gate: only `true` entries |
| Provider `doc` | `ModelCard.sourceURL` |

**What it does NOT have** (sourced elsewhere):

- Quantization variants, GGUF sizes, Ollama tags, LM Studio IDs, memory requirements

```swift
// Sources/CatalogGenerator/Pipeline/ModelsDevClient.swift

struct ModelsDevClient {
    static let apiURL = URL(string: "https://models.dev/api.json")!

    func fetchOpenWeightModels() async throws -> [ModelsDevEntry] {
        let (data, _) = try await URLSession.shared.data(from: Self.apiURL)
        let providers = try JSONDecoder().decode(
            [String: ModelsDevProvider].self, from: data
        )

        var entries: [ModelsDevEntry] = []
        for (providerID, provider) in providers {
            for (modelID, model) in provider.models where model.openWeights == true {
                entries.append(ModelsDevEntry(
                    fullID: "\(providerID)/\(modelID)",
                    providerID: providerID,
                    modelID: modelID,
                    name: model.name,
                    family: model.family,
                    releaseDate: model.releaseDate,
                    providerName: provider.name,
                    providerDoc: provider.doc
                ))
            }
        }
        return entries
    }
}
```

**Deduplication:** The same model may appear under multiple providers (Meta, OpenRouter, Together). Only models with entries in the model map (§4.2) are included — the map key contains the canonical provider.

### 4.2 Layer 1: Model Map

The bridge between models.dev and the local inference world. A JSON file at `data/model-map.json`:

```json
{
  "meta/llama-3.1-8b-instruct": {
    "ollama": "llama3.1",
    "hf_gguf": "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF",
    "params_b": 8.0
  },
  "meta/llama-3.1-70b-instruct": {
    "ollama": "llama3.1:70b",
    "hf_gguf": "lmstudio-community/Meta-Llama-3.1-70B-Instruct-GGUF",
    "params_b": 70.0
  },
  "meta/llama-3.3-70b-instruct": {
    "ollama": "llama3.3",
    "hf_gguf": "lmstudio-community/Meta-Llama-3.3-70B-Instruct-GGUF",
    "params_b": 70.0
  },
  "mistralai/mistral-7b-instruct": {
    "ollama": "mistral",
    "hf_gguf": "TheBloke/Mistral-7B-Instruct-v0.2-GGUF",
    "params_b": 7.0
  },
  "mistralai/mixtral-8x7b-instruct": {
    "ollama": "mixtral",
    "hf_gguf": "TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF",
    "params_b": 46.7
  },
  "microsoft/phi-3-mini-4k-instruct": {
    "ollama": "phi3",
    "hf_gguf": "microsoft/Phi-3-mini-4k-instruct-gguf",
    "params_b": 3.8
  },
  "google/gemma-2-9b-it": {
    "ollama": "gemma2:9b",
    "hf_gguf": "lmstudio-community/gemma-2-9b-it-GGUF",
    "params_b": 9.0
  },
  "qwen/qwen-2.5-7b-instruct": {
    "ollama": "qwen2.5:7b",
    "hf_gguf": "Qwen/Qwen2.5-7B-Instruct-GGUF",
    "params_b": 7.0
  },
  "deepseek/deepseek-r1-distill-qwen-7b": {
    "ollama": "deepseek-r1:7b",
    "hf_gguf": "lmstudio-community/DeepSeek-R1-Distill-Qwen-7B-GGUF",
    "params_b": 7.0
  }
}
```

```swift
// Sources/CatalogGenerator/Types/ModelMapEntry.swift

struct ModelMapEntry: Codable {
    let ollama: String
    let hfGguf: String?
    let paramsB: Double

    enum CodingKeys: String, CodingKey {
        case ollama
        case hfGguf = "hf_gguf"
        case paramsB = "params_b"
    }
}

// Sources/CatalogGenerator/Pipeline/ModelMapLoader.swift

struct ModelMapLoader {
    func load(from path: String) throws -> [String: ModelMapEntry] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: ModelMapEntry].self, from: data)
    }
}
```

**What the map controls:**
- **Inclusion:** Only mapped models appear in the catalog. This is the quality gate.
- **Identity:** Which models.dev entry is canonical.
- **Naming:** Ollama model names and HuggingFace GGUF repos.
- **Parameters:** Exact count in billions (critical for MoE models where APIs report active instead of total params).

**What the map does NOT contain:** Names, families, release dates — those come from models.dev. File sizes, quantizations, Ollama tags — those come from API enrichment.

### 4.3 Layer 2: Ollama Registry

For each mapped model, the generator queries the Ollama registry for available tags and sizes.

```swift
// Sources/CatalogGenerator/Pipeline/OllamaRegistryClient.swift

struct OllamaRegistryClient {
    private static let baseURL = "https://registry.ollama.com"

    func fetchTags(for model: String) async throws -> [OllamaTag] {
        let modelName = model.split(separator: ":").first.map(String.init) ?? model
        let url = URL(string: "\(Self.baseURL)/v2/library/\(modelName)/tags/list")!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }

        let tagList = try JSONDecoder().decode(OllamaTagList.self, from: data)
        return tagList.tags.compactMap { tag in
            guard let quant = Self.extractQuantization(from: tag.name) else {
                return nil
            }
            return OllamaTag(
                fullTag: "\(modelName):\(tag.name)",
                quantization: quant,
                sizeBytes: tag.totalSize
            )
        }
    }

    private static let quantPatterns: [(String, String)] = [
        ("q2_k", "Q2_K"),   ("q3_k_s", "Q3_K_S"), ("q3_k_m", "Q3_K_M"),
        ("q4_0", "Q4_0"),   ("q4_k_s", "Q4_K_S"), ("q4_k_m", "Q4_K_M"),
        ("q5_0", "Q5_0"),   ("q5_k_s", "Q5_K_S"), ("q5_k_m", "Q5_K_M"),
        ("q6_k", "Q6_K"),   ("q8_0", "Q8_0"),
        ("fp16", "F16"),    ("f16", "F16"),
    ]

    static func extractQuantization(from tag: String) -> String? {
        let lower = tag.lowercased()
        for (pattern, quant) in quantPatterns {
            if lower.contains(pattern) { return quant }
        }
        return nil
    }
}
```

**Target quantizations:**

| Quantization | Include | Rationale |
|-------------|---------|-----------|
| Q4_K_M | Always | Best quality-to-size ratio. Most popular. |
| Q5_K_M | Always | Higher quality, moderate size increase. |
| Q8_0 | Always | Near-lossless for ample memory. |
| Q3_K_M | If available | Memory-constrained systems. |
| Q6_K | If available | Between Q5 and Q8. |
| Q2_K | If available | Minimum viable quality. |
| F16 | If available | Full precision reference. |

### 4.4 Layer 3: HuggingFace Enrichment

For models with an `hf_gguf` mapping, the generator queries HuggingFace for GGUF file metadata.

```swift
// Sources/CatalogGenerator/Pipeline/HuggingFaceClient.swift

struct HuggingFaceClient {
    private let token: String?

    init(token: String? = ProcessInfo.processInfo.environment["HF_TOKEN"]) {
        self.token = token
    }

    func fetchGGUFFiles(repo: String) async throws -> [HuggingFaceFile] {
        var request = URLRequest(
            url: URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        )
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }

        let model = try JSONDecoder().decode(HFModelResponse.self, from: data)
        return model.siblings
            .filter { $0.rfilename.hasSuffix(".gguf") }
            .compactMap { file in
                guard let quant = OllamaRegistryClient.extractQuantization(
                    from: file.rfilename
                ) else { return nil }
                return HuggingFaceFile(
                    filename: file.rfilename,
                    quantization: quant,
                    sizeBytes: file.size,
                    downloadURL: URL(string:
                        "https://huggingface.co/\(repo)/resolve/main/\(file.rfilename)"
                    )
                )
            }
    }
}
```

### 4.5 Memory Requirements

The same formula from RFC-003 §3.8, using calibrated `gbPerBillionParams` values validated against real Ollama sizes (aligned with [llm-checker](https://github.com/Pavelevich/llm-checker)):

```swift
// Sources/CatalogGenerator/Pipeline/RequirementsCalculator.swift

struct RequirementsCalculator {
    private static let gbPerBillionParams: [String: Double] = [
        "Q2_K": 0.37,  "Q3_K_S": 0.44, "Q3_K_M": 0.48,
        "Q4_0": 0.54,  "Q4_K_S": 0.56, "Q4_K_M": 0.58,
        "Q5_0": 0.63,  "Q5_K_S": 0.66, "Q5_K_M": 0.68,
        "Q6_K": 0.80,  "Q8_0":   1.05,
        "F16":  2.00,  "F32":    4.00,
    ]

    private static let defaultContextLength: Double = 4096
    private static let runtimeOverheadGB: Double = 0.5
    private static let kvCacheFactorPerBPerToken: Double = 0.000008

    static func compute(
        paramsBillion: Double,
        quantization: String,
        diskSizeBytes: UInt64
    ) -> CatalogRequirements {
        let gbpp = gbPerBillionParams[quantization] ?? 0.58
        let weightsGB = paramsBillion * gbpp
        let kvCacheGB = kvCacheFactorPerBPerToken * paramsBillion * defaultContextLength
        let minimumGB = weightsGB + kvCacheGB + runtimeOverheadGB
        let recommendedGB = minimumGB * 1.2

        let oneGB: UInt64 = 1_073_741_824
        return CatalogRequirements(
            minimumMemoryBytes: UInt64(minimumGB * Double(oneGB)),
            recommendedMemoryBytes: UInt64(recommendedGB * Double(oneGB)),
            diskSizeBytes: diskSizeBytes
        )
    }
}
```

## 5. Validation

The generator validates output by **decoding it through the same schema types** that RFC-003 defines. If the JSON decodes into `CatalogFile` (which contains `[ModelCard]` with `[ModelVariant]`), it is schema-valid by construction.

```swift
// Sources/CatalogGenerator/Validation/CatalogValidator.swift

struct CatalogValidator {
    func validate(_ catalog: CatalogOutput) throws {
        let encoded = try JSONEncoder().encode(catalog)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        _ = try decoder.decode(CatalogFile.self, from: encoded)

        try checkNoDuplicateIDs(catalog)
        try checkRequirementsSanity(catalog)
        try checkAllModelsHaveVariants(catalog)
    }

    private func checkNoDuplicateIDs(_ catalog: CatalogOutput) throws {
        var seen = Set<String>()
        for model in catalog.models {
            guard seen.insert(model.id).inserted else {
                throw ValidationError.duplicateModelID(model.id)
            }
            var variantSeen = Set<String>()
            for variant in model.variants {
                guard variantSeen.insert(variant.id).inserted else {
                    throw ValidationError.duplicateVariantID(variant.id, model: model.id)
                }
            }
        }
    }

    private func checkRequirementsSanity(_ catalog: CatalogOutput) throws {
        for model in catalog.models {
            for variant in model.variants {
                let req = variant.requirements
                guard req.recommendedMemoryBytes > req.minimumMemoryBytes else {
                    throw ValidationError.invalidRequirements(
                        variant: variant.id,
                        reason: "recommended must exceed minimum"
                    )
                }
            }
        }
    }

    private func checkAllModelsHaveVariants(_ catalog: CatalogOutput) throws {
        for model in catalog.models where model.variants.isEmpty {
            throw ValidationError.noVariants(model: model.id)
        }
    }
}
```

The `CatalogFile` type used for decode validation is the same `internal struct CatalogFile` from RFC-003 §4.2. The generator includes a copy of the relevant types in `Sources/CatalogGenerator/Types/CatalogOutput.swift` to avoid depending on the `FitCheck` target (which requires Metal).

## 6. Entry Point

```swift
// Sources/CatalogGenerator/CatalogGenerator.swift

import Foundation

@main
struct CatalogGenerator {
    static func main() async throws {
        let args = CommandLine.arguments
        let dryRun = args.contains("--dry-run")
        let discover = args.contains("--discover")
        let offline = args.contains("--offline")
        let verbose = args.contains("--verbose")

        let modelsDevClient = ModelsDevClient()
        let modelMapLoader = ModelMapLoader()
        let ollamaClient = OllamaRegistryClient()
        let hfClient = HuggingFaceClient()
        let validator = CatalogValidator()

        // Layer 0: models.dev
        let openWeightModels = try await modelsDevClient.fetchOpenWeightModels()
        log("models.dev: \(openWeightModels.count) open-weight models", verbose: verbose)

        // Layer 1: Model map
        let modelMap = try modelMapLoader.load(from: "data/model-map.json")

        if discover {
            printUnmappedModels(openWeightModels, modelMap)
            return
        }

        let mapped = openWeightModels.filter { modelMap[$0.fullID] != nil }
        log("Mapped: \(mapped.count) models with local inference data", verbose: verbose)

        // Layer 2+3: Enrich and compute
        var catalogModels: [CatalogModel] = []
        for entry in mapped {
            guard let mapping = modelMap[entry.fullID] else { continue }

            var card = CatalogModel(from: entry, mapping: mapping)

            if !offline {
                let ollamaTags = try? await ollamaClient.fetchTags(for: mapping.ollama)
                let hfFiles = try? await hfClient.fetchGGUFFiles(repo: mapping.hfGguf ?? "")
                card.variants = VariantMerger.merge(
                    ollama: ollamaTags ?? [],
                    huggingFace: hfFiles ?? [],
                    paramsB: mapping.paramsB
                )
            } else {
                card.variants = VariantMerger.formulaOnly(paramsB: mapping.paramsB)
            }

            if !card.variants.isEmpty {
                catalogModels.append(card)
            }
        }

        // Layer 4: Overrides
        let overrides = try? loadOverrides(from: "data/overrides.json")
        if let overrides {
            catalogModels = catalogModels.map { applyOverrides($0, overrides) }
        }

        let catalog = CatalogOutput(
            version: "1.0.0",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            models: catalogModels.sorted { $0.name < $1.name }
        )

        // Validate
        try validator.validate(catalog)

        // Output
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(catalog)

        if dryRun {
            print("Validation passed. \(catalog.models.count) models, "
                + "\(catalog.models.flatMap(\.variants).count) variants.")
            return
        }

        try jsonData.write(to: URL(fileURLWithPath: "data/catalog.json"))
        try jsonData.write(to: URL(fileURLWithPath:
            "Sources/FitCheck/Resources/bundled-catalog.json"))

        print("Generated \(catalog.models.count) models, "
            + "\(catalog.models.flatMap(\.variants).count) variants.")
    }
}
```

## 7. CI Automation

```yaml
# .github/workflows/update-catalog.yml

name: Update Model Catalog

on:
  schedule:
    - cron: '0 6 * * 1'  # Weekly on Monday at 06:00 UTC
  workflow_dispatch:

permissions:
  contents: write

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.0'

      - name: Generate catalog
        env:
          HF_TOKEN: ${{ secrets.HF_TOKEN }}
        run: swift run CatalogGenerator --verbose

      - name: Check for changes
        id: diff
        run: |
          if git diff --quiet data/catalog.json; then
            echo "changed=false" >> $GITHUB_OUTPUT
          else
            echo "changed=true" >> $GITHUB_OUTPUT
          fi

      - name: Commit and push
        if: steps.diff.outputs.changed == 'true'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add data/catalog.json Sources/FitCheck/Resources/bundled-catalog.json
          git commit -m "chore: update model catalog"
          git push
```

The generator uses only `Foundation` (no Metal, no AppKit), so it compiles and runs on Linux CI runners. Weekly schedule with manual `workflow_dispatch` for urgent additions.

## 8. Discovery

The `--discover` flag compares models.dev's open-weight entries against the model map:

```bash
$ swift run CatalogGenerator --discover

Open-weight models on models.dev without FitCheck mappings:

  google/gemma-3-27b-it            family: gemma     released: 2025-03-12
  nvidia/nemotron-3-nano-4b        family: nemotron   released: 2025-06-15
  alibaba/qwen-3.5-35b-instruct   family: qwen       released: 2025-09-01

3 unmapped models found.
To add: create an entry in data/model-map.json
```

## 9. Adding New Models

### For contributors

Adding a model requires editing **one file** (`data/model-map.json`). Three fields:

```json
{
  "google/gemma-3-27b-it": {
    "ollama": "gemma3:27b",
    "hf_gguf": "lmstudio-community/gemma-3-27b-it-GGUF",
    "params_b": 27.0
  }
}
```

No Swift knowledge needed. Submit a PR.

### When a model isn't on models.dev yet

Submit a PR to [anomalyco/models.dev](https://github.com/anomalyco/models.dev) with a TOML file. Once merged, add the mapping to FitCheck.

## 10. File Structure

```
data/
├── catalog.json              # Generated (DO NOT EDIT)
├── model-map.json            # models.dev → Ollama/HF mapping (EDIT THIS)
└── overrides.json            # Manual corrections (EDIT THIS)

Sources/CatalogGenerator/
├── CatalogGenerator.swift    # @main entry point
├── Pipeline/
│   ├── ModelsDevClient.swift
│   ├── OllamaRegistryClient.swift
│   ├── HuggingFaceClient.swift
│   ├── ModelMapLoader.swift
│   ├── VariantMerger.swift
│   └── RequirementsCalculator.swift
├── Validation/
│   └── CatalogValidator.swift
└── Types/
    ├── CatalogOutput.swift   # Encodable output types (mirrors RFC-003 schema)
    ├── ModelsDevTypes.swift   # Decodable types for models.dev API
    └── ModelMapEntry.swift

Sources/FitCheck/Resources/
└── bundled-catalog.json      # Copy of data/catalog.json (generated)
```

## 11. Error Handling

| Scenario | Detection | Recovery |
|----------|-----------|---------|
| models.dev unreachable | `URLSession` error | Abort. models.dev is the foundation. Use `--offline` with a previously generated catalog for development. |
| Ollama registry unreachable | Connection error | Warning, skip enrichment. Compute sizes from formula. |
| HuggingFace rate limited | HTTP 429 | Retry with exponential backoff (1s → 30s). After 5 retries, skip HF for this model. |
| Model in map but removed from models.dev | Map key not found | Warning, skip model. |
| No variants found for a model | Ollama has no tags, HF has no files | Warning, drop model from catalog. |
| Validation failure | `CatalogValidator` throws | Abort. Do not write output files. |

## 12. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Python generator script | Introduces a second language and toolchain into a Swift package. Contributors now need Python. CI needs two runtimes. Inconsistent with the project identity. |
| Hand-curated TOML per model family | Duplicates curation that models.dev already does. Requires tracking names, families, release dates manually. models.dev has a community doing this. |
| Import `FitCheck` library in the generator | `FitCheck` depends on Metal (for hardware profiling). Metal is unavailable on Linux CI. The generator defines its own lightweight output types that mirror the schema. |
| TOML model map | Foundation has no TOML decoder. Would need a dependency or custom parser. JSON works natively with `JSONDecoder`. |
| SPM build plugin instead of executable target | Build plugins run during `swift build` — network calls during builds break reproducibility and offline development. An executable target runs explicitly when invoked. |
| Daily CI schedule | Model releases happen 2–4 times per month. Weekly + manual dispatch is sufficient. |

## 13. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | What is the model index? | **models.dev `api.json`, filtered to `open_weights == true`.** Community-curated, actively maintained, MIT licensed. FitCheck piggybacks on their curation. |
| 2 | Why a model map? | **`data/model-map.json` bridges models.dev IDs to Ollama/HuggingFace names.** No API can map between these naming schemes. The map is also the inclusion gate. Three fields per model. |
| 3 | What language for the generator? | **Swift.** Same toolchain as the package. Executable target in `Package.swift`. Uses only Foundation — runs on macOS and Linux. `swift run CatalogGenerator`. |
| 4 | Why not depend on the `FitCheck` library target? | **Metal dependency.** `FitCheck` imports Metal for hardware profiling. Metal is unavailable on Linux. The generator copies the relevant output types. Validation tests in `FitCheckTests` verify the bundled catalog decodes into `[ModelCard]`. |
| 5 | How to validate output? | **Decode through RFC-003 types.** The generator encodes to JSON, then the `CatalogValidator` decodes it through `CatalogFile`/`ModelCard`/`ModelVariant` types. If it decodes, the schema is correct by construction. |
| 6 | How often to regenerate? | **Weekly cron + manual `workflow_dispatch`.** |
| 7 | What if models.dev goes down? | **Short term: generator fails, existing catalog untouched. Long term: fork.** models.dev is MIT-licensed. The model map already contains enough data to generate a degraded catalog from Ollama + formula alone. |
| 8 | How to discover new models? | **`--discover` flag.** Compares models.dev open-weight entries against the model map. Shows unmapped candidates. |
