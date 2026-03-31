# FitCheck

A Swift package for macOS that tells you which open-weight AI models can run on your Mac.

FitCheck detects your Apple Silicon hardware, checks it against a catalog of 100+ open-weight models, and tells you exactly what fits — with download instructions for [Ollama](https://ollama.com) and [LM Studio](https://lmstudio.ai).

## Quick Start

```swift
import FitCheck

let fc = FitCheck()
let models = try await fc.compatibleModels()

for model in models {
    print("\(model.card.displayName) — \(model.variant.quantization.displayName)")
    print("  \(model.report.verdict)")

    if let ollama = model.ollamaAction {
        print("  \(ollama.displayInstructions)")
    }
}
```

## Installation

Add FitCheck to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nicklama/FitCheck.git", from: "0.1.0")
]
```

Then add `"FitCheck"` to your target's dependencies.

**Requirements:** macOS 14+, Apple Silicon, Swift 6.2+

## What It Does

**Hardware profiling** — Detects your chip (M1–M4, all tiers), total memory, GPU cores, and Neural Engine. Computes available memory using a calibrated utilization formula.

**Model catalog** — Ships with a bundled catalog of open-weight models across all major families (Llama, Mistral, Phi, Gemma, Qwen, DeepSeek, and more). Auto-updates from GitHub so even old installations see new models.

**Compatibility verdicts** — Matches hardware against model requirements and produces clear verdicts: optimal, comfortable, constrained, marginal, or incompatible. Memory estimation uses calibrated bytes-per-parameter values validated against real Ollama sizes.

**Download actions** — Generates ready-to-use download instructions for Ollama (`ollama pull ...`) and LM Studio (`lms get ...`). Detects which tools are installed.

## API

```swift
let fc = FitCheck()

// What can I run?
let compatible = try await fc.compatibleModels()

// Check a specific model
let reports = try await fc.check(modelID: "llama-3.1-8b-instruct")

// What's my hardware?
let profile = try await fc.hardwareProfile()

// Filter models
let small = try await fc.models(maxParameters: 8)
let llamas = try await fc.models(family: .llama)
let results = try await fc.models(matching: "deepseek")

// Provider status
let providers = try await fc.providers()
let installed = try await fc.installedModels()
```

## Architecture

FitCheck is protocol-oriented with concrete defaults. Every subsystem is injectable for testing:

```swift
// Custom configuration
let fc = FitCheck(
    catalogProvider: BundledCatalogProvider(),  // offline only
    downloadProviders: [OllamaProvider()]       // Ollama only
)
```

| Component | Protocol | Default |
|-----------|----------|---------|
| Hardware detection | `HardwareProfiler` | `SystemHardwareProfiler` |
| Model data | `CatalogProvider` | Remote + bundled composite |
| Compatibility | `CompatibilityChecker` | `DefaultCompatibilityChecker` |
| Downloads | `DownloadProvider` | Ollama + LM Studio |

## Catalog

The model catalog is sourced from [models.dev](https://models.dev) (open-weight models) and enriched with Ollama/HuggingFace metadata. Memory requirements use calibrated values from [llm-checker](https://github.com/Pavelevich/llm-checker).

**Update the catalog:**

```bash
swift run CatalogGenerator
```

**Add a model:** Edit `data/model-map.json` with three fields:

```json
{
  "provider/model-id": {
    "ollama": "model-name",
    "hf_gguf": "org/Model-GGUF",
    "params_b": 7.0
  }
}
```

**Discover unmapped models:**

```bash
swift run CatalogGenerator --discover
```

## Design Decisions

- **Apple Silicon only** — Intel Macs lack unified memory and Neural Engine. Local LLM inference is impractical on them.
- **Zero dependencies** — Uses only Apple system frameworks (Foundation, Metal, OSLog).
- **Swift 6 strict concurrency** — The `FitCheck` entry point is an actor. All types are `Sendable`.
- **Generate actions, don't execute** — FitCheck tells you *how* to download a model. Your app decides *when*.
- **Calibrated memory estimates** — `Q4_K_M` uses 0.58 GB per billion parameters (not theoretical 0.5). Validated against real Ollama download sizes.

## Project Structure

```
Sources/FitCheck/          Library (import FitCheck)
Sources/CatalogGenerator/  Catalog generation tool
Tests/FitCheckTests/       Test suite (51 tests)
data/                      Model map and overrides
docs/rfcs/                 Design documents
```

## Contributing

1. Fork the repository
2. To add a model: edit `data/model-map.json`
3. To add a model family: edit `Sources/FitCheck/Catalog/ModelFamily.swift`
4. Run `swift test` to verify
5. Submit a PR

## License

MIT
