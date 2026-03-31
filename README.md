# FitCheck

A Swift package for macOS that tells you which open-weight AI models can run on your Mac.

FitCheck detects your Apple Silicon hardware, checks it against a catalog of 100+ open-weight models, and tells you exactly what fits — with download instructions for [Ollama](https://ollama.com) and [LM Studio](https://lmstudio.ai), and estimated inference speed.

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
    .package(url: "https://github.com/Maia-jp/FitCheck.git", from: "0.1.0")
]
```

Then add `"FitCheck"` to your target's dependencies.

**Requirements:** macOS 14+, Apple Silicon, Swift 6.2+

## What It Does

**Hardware profiling** — Detects your chip (M1–M4, all tiers), total memory, GPU cores, Neural Engine, and memory bandwidth. Computes available memory using a calibrated utilization formula.

**Model catalog** — Ships with 106 open-weight models across 24 families (Llama, Mistral, Phi, Gemma, Qwen, DeepSeek, and more). Auto-updates from GitHub so even old installations see new models.

**Compatibility verdicts** — Matches hardware against model requirements and produces clear verdicts: optimal, comfortable, constrained, marginal, or incompatible. Supports MoE models (Mixtral, DeepSeek V3) and configurable context lengths. Memory estimation uses calibrated values validated against real Ollama sizes.

**Performance estimation** — Estimates tokens/second based on your chip's memory bandwidth and the model size. Know whether a model will be fast or frustratingly slow before downloading.

**Download actions** — Generates ready-to-use download instructions for Ollama (`ollama pull ...`) and LM Studio (`lms get ...`). Detects which tools are installed.

## API

```swift
let fc = FitCheck()

// What can I run from the catalog?
let compatible = try await fc.compatibleModels()

// Check a specific catalog model
let reports = try await fc.check(modelID: "llama3-1-8b")

// What's my hardware?
let profile = try await fc.hardwareProfile()

// Filter catalog
let small = try await fc.models(maxParameters: 8)
let llamas = try await fc.models(family: .llama)
let results = try await fc.models(matching: "deepseek")

// Provider status
let providers = try await fc.providers()
let installed = try await fc.installedModels()
```

## Custom Models

You don't need to use the catalog. Check any model spec directly — your own fine-tunes, new releases, anything:

```swift
let fc = FitCheck()

// "Can my Mac run a 13B model at Q4_K_M with 8K context?"
let report = try await fc.checkCustom(
    parametersBillion: 13,
    quantization: .q4KM,
    contextLength: 8192
)

print(report.summary)
// "13B Q4_K_M: Compatible (Comfortable) — 8.6 GB, ~14.5 tok/s"

print(report.verdict)              // Compatible (Comfortable)
print(report.requirements.minimumMemoryGB)  // 8.6
print(report.performanceEstimate.rating)    // Moderate (15–30 tok/s)
print(report.isRunnable)           // true
```

Use the calculation engine directly for full control:

```swift
// Estimate memory for any model spec
let requirements = ModelRequirements.estimated(
    parameterCount: ParameterCount(billions: 70),
    quantization: .q4KM,
    diskSizeBytes: 40_000_000_000,
    contextLength: 32768  // 32K context
)
print(requirements.minimumMemoryGB)  // ~45 GB

// Estimate inference speed on any chip
let profile = try await FitCheck().hardwareProfile()
let perf = PerformanceCalculator.estimate(
    modelSizeGB: 40.0,
    hardware: profile
)
print(perf.estimatedTokensPerSecond)  // varies by chip
print(perf.rating)                    // e.g. "Slow (8–15 tok/s)"

// Check memory bandwidth for any Apple Silicon variant
let bandwidth = PerformanceCalculator.memoryBandwidth(
    for: .appleSilicon(.m4Max)
)
print(bandwidth)  // 546.0 GB/s
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

**Add a model:** Edit `data/model-map.json`:

```json
{
  "ollama/llama3.1:8b": {
    "ollama": "llama3.1:8b",
    "name": "Llama 3.1 8B",
    "family": "llama",
    "hf_gguf": "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF",
    "params_b": 8.0
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
- **MoE awareness** — Mixture-of-Experts models (Mixtral, DeepSeek V3) use active parameters for memory estimation, not total parameters.

## Project Structure

```
Sources/FitCheck/          Library (import FitCheck)
Sources/CatalogGenerator/  Catalog generation tool
Tests/FitCheckTests/       Test suite (61 tests)
data/                      Model map
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
