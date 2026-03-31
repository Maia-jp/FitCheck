# RFC-001: Project Foundation & Package Architecture

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | —                                           |
| Phase       | 1                                           |

---

## 1. Motivation

FitCheck currently has a skeleton `Package.swift` with no implementation. Before any feature work begins, the project needs a well-defined package structure, platform targets, dependency policy, shared error model, and coding conventions. Without these foundations, parallel development across RFC-002 through RFC-006 would produce inconsistent code with incompatible patterns.

This RFC defines the package manifest, module layout, error model, logging strategy, and the engineering conventions every subsequent RFC must follow.

## 2. Package Architecture Overview

FitCheck is a single-module Swift package library. Consumers add it via Swift Package Manager and import `FitCheck` to access all public API.

```
┌─────────────────────────────────────────────────┐
│                  Consumer App                    │
│                                                  │
│   import FitCheck                                │
│   let fc = FitCheck()                            │
│   let models = try await fc.compatibleModels()   │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│              FitCheck Module                     │
│                                                  │
│  ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │ Hardware │ │ Catalog  │ │ Compatibility  │  │
│  │ (§RFC-002)│ │(§RFC-003)│ │  (§RFC-004)    │  │
│  └────┬─────┘ └────┬─────┘ └───────┬────────┘  │
│       │             │               │            │
│  ┌────┴─────────────┴───────────────┴────────┐  │
│  │           Providers (§RFC-005)             │  │
│  └───────────────────────────────────────────┘  │
│                                                  │
│  ┌───────────────────────────────────────────┐  │
│  │         Public API (§RFC-006)             │  │
│  └───────────────────────────────────────────┘  │
│                                                  │
│  ┌───────────────────────────────────────────┐  │
│  │  Errors (§4) │ Logging (§5)               │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### 2.1 Design Principles

1. **Zero external dependencies.** FitCheck relies exclusively on Apple system frameworks (`Foundation`, `Metal`, `IOKit`). This eliminates version conflicts, supply-chain risk, and build complexity for consumers.

2. **Protocol-oriented with concrete defaults.** Every subsystem defines a protocol (`HardwareProfiler`, `CatalogProvider`, `CompatibilityChecker`, `DownloadProvider`) with a production implementation. Consumers can substitute any implementation for testing or customization.

3. **Value types for data, reference types for coordination.** All models (`ModelCard`, `HardwareProfile`, `CompatibilityReport`) are structs. The top-level `FitCheck` coordinator is an `actor` for safe concurrent access.

4. **Strict Swift 6 concurrency.** All types crossing concurrency domains conform to `Sendable`. The package compiles with `StrictConcurrency` enabled and zero warnings.

## 3. Package Manifest

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FitCheck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FitCheck",
            targets: ["FitCheck"]
        ),
    ],
    targets: [
        .target(
            name: "FitCheck",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FitCheckTests",
            dependencies: ["FitCheck"]
        ),
        .executableTarget(
            name: "CatalogGenerator",
            path: "Sources/CatalogGenerator"
        ),
    ]
)
```

### 3.1 Platform Target Rationale

macOS 14 (Sonoma) is the minimum deployment target because:
- Metal 3 API availability for GPU introspection
- Swift 5.9+ concurrency runtime maturity
- `ProcessInfo` enhancements for thermal and memory pressure
- Covers all Apple Silicon Macs still receiving security updates

### 3.2 Resource Bundle

The `Resources/` directory contains `bundled-catalog.json` (defined in RFC-003 §5). Swift Package Manager processes this into `Bundle.module`, accessible at runtime via `Bundle.module.url(forResource:withExtension:)`.

## 4. Error Model

All errors surfaced by FitCheck are expressed through a single `FitCheckError` enum. This gives consumers one type to catch and pattern-match against.

```swift
// Sources/FitCheck/Errors/FitCheckError.swift  [new file]

public enum FitCheckError: Error, Sendable {
    case hardwareDetectionFailed(reason: String)
    case catalogLoadFailed(underlying: any Error)
    case catalogDecodingFailed(path: String, underlying: any Error)
    case networkUnavailable(underlying: any Error)
    case providerNotInstalled(provider: String)
    case shellCommandFailed(command: String, exitCode: Int32, stderr: String)
    case modelNotFound(identifier: String)
    case unsupportedPlatform(detected: String)
    case resourceMissing(name: String)
}

extension FitCheckError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .hardwareDetectionFailed(let reason):
            return "Hardware detection failed: \(reason)"
        case .catalogLoadFailed(let underlying):
            return "Failed to load model catalog: \(underlying.localizedDescription)"
        case .catalogDecodingFailed(let path, let underlying):
            return "Failed to decode catalog at \(path): \(underlying.localizedDescription)"
        case .networkUnavailable(let underlying):
            return "Network unavailable: \(underlying.localizedDescription)"
        case .providerNotInstalled(let provider):
            return "\(provider) is not installed on this system"
        case .shellCommandFailed(let command, let exitCode, let stderr):
            return "Command '\(command)' failed with exit code \(exitCode): \(stderr)"
        case .modelNotFound(let identifier):
            return "No model found with identifier '\(identifier)'"
        case .unsupportedPlatform(let detected):
            return "Unsupported platform: \(detected). FitCheck requires macOS on Apple Silicon."
        case .resourceMissing(let name):
            return "Required resource '\(name)' not found in bundle"
        }
    }
}
```

### 4.1 Error Design Rationale

| Decision | Rationale |
|----------|-----------|
| Single enum (not per-subsystem enums) | Consumers catch one type. Internal subsystems throw `FitCheckError` directly — no wrapping layers. |
| Associated values over nested types | Keeps the error enum flat and switch-friendly. Avoids `FitCheckError.Hardware.detectionFailed` verbosity. |
| `any Error` for `underlying` | Preserves the original system error for debugging without coupling to specific framework error types. |
| `Sendable` conformance | Required for throwing across concurrency domains under Swift 6. |

## 5. Logging

FitCheck uses `os.Logger` from the unified logging system. Each subsystem creates a logger scoped to its category, enabling fine-grained filtering with `Console.app` or `log stream`.

```swift
// Sources/FitCheck/Logging.swift  [new file]

import OSLog

enum Log {
    static let subsystem = "com.fitcheck"

    static let hardware = Logger(subsystem: subsystem, category: "hardware")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
    static let compatibility = Logger(subsystem: subsystem, category: "compatibility")
    static let providers = Logger(subsystem: subsystem, category: "providers")
    static let api = Logger(subsystem: subsystem, category: "api")
}
```

### 5.1 Logging Conventions

| Level    | Usage                                                          |
|----------|----------------------------------------------------------------|
| `.debug` | Detailed internal state (memory values, model counts, paths)  |
| `.info`  | Lifecycle events (profile loaded, catalog refreshed)           |
| `.error` | Recoverable failures (network timeout, missing provider)       |
| `.fault` | Unrecoverable state (corrupted bundle, impossible enum case)   |

Logs never contain user-identifiable information. Hardware specs (chip type, memory size) are logged at `.debug` level only.

## 6. Source Layout

```
Sources/FitCheck/
├── FitCheck.swift                     ← Public API entry point (RFC-006)
├── Logging.swift                      ← os.Logger instances (this RFC)
├── Errors/
│   └── FitCheckError.swift            ← Error enum (this RFC)
├── Hardware/                          ← RFC-002
├── Catalog/                           ← RFC-003
├── Compatibility/                     ← RFC-004
├── Providers/                         ← RFC-005
└── Resources/
    └── bundled-catalog.json           ← RFC-003
```

Each subdirectory maps 1:1 to an RFC. Files within a directory are named after the primary type they define (one public type per file).

## 7. Coding Conventions

### 7.1 Type Design

| Pattern | Rule |
|---------|------|
| Data models | `struct`, `Sendable`, `Codable`, `Equatable` |
| Protocols | One protocol per file, marked `Sendable` when implementations cross isolation domains |
| Implementations | `struct` for stateless, `actor` for stateful concurrent access |
| Enums | Explicit `String` raw values when the value appears in JSON or CLI output |
| Access control | `public` on API surface, `internal` on implementation helpers, `private` on stored state |

### 7.2 Concurrency

| Pattern | Rule |
|---------|------|
| Async entry points | All public methods that perform I/O are `async throws` |
| Actor isolation | The top-level `FitCheck` type is an `actor` — callers `await` its methods |
| Sendable | Every type passed across isolation boundaries conforms to `Sendable` |
| Task cancellation | Long-running operations check `Task.isCancelled` and throw `CancellationError` |
| No Combine | Use `async`/`await` and `AsyncSequence` exclusively. No `Publisher` types in public API. |

### 7.3 Naming

| Entity | Convention | Example |
|--------|------------|---------|
| Types | PascalCase | `ModelCard`, `HardwareProfile` |
| Properties / methods | camelCase | `parameterCount`, `fetchModels()` |
| Enum cases | camelCase | `.compatible`, `.insufficientMemory` |
| Files | PascalCase matching primary type | `ModelCard.swift` |
| Directories | PascalCase for feature groups | `Hardware/`, `Catalog/` |
| Constants | camelCase | `systemMemoryOverheadBytes` |

### 7.4 Testing

| Pattern | Rule |
|---------|------|
| Protocol mocks | Define `Mock<Protocol>` structs inside test files, conforming to the protocol |
| Test naming | `test_<method>_<scenario>_<expectedOutcome>` |
| No network in tests | All tests use injected mock providers; no real HTTP or shell calls |
| Test target | `FitCheckTests` mirrors source directory structure |

## 8. Error Handling

| Scenario | Detection | Recovery |
|----------|-----------|---------|
| Bundle resource missing at runtime | `Bundle.module.url(forResource:)` returns `nil` | Throw `.resourceMissing(name:)`. Consumer must verify package is correctly integrated. |
| Unsupported platform (iOS, Linux) | `#if` compilation check + runtime `ProcessInfo` check | Throw `.unsupportedPlatform(detected:)`. FitCheck is macOS-only. |
| Swift concurrency violation | Compile-time via strict concurrency mode | No runtime recovery needed — caught at build time. |

## 9. Dependency Policy

FitCheck has zero third-party dependencies. The rationale:

| Concern | Decision |
|---------|----------|
| JSON decoding | `Foundation.JSONDecoder` — sufficient for the catalog schema |
| HTTP requests | `Foundation.URLSession` — built into macOS |
| Shell execution | `Foundation.Process` — built into macOS |
| GPU detection | `Metal` framework — system framework |
| Hardware introspection | `sysctl` via Darwin C interop + `ProcessInfo` |
| Logging | `OSLog` — system framework |

Third-party dependencies are only acceptable if they meet all three criteria: (1) solve a problem no system framework can, (2) are maintained by a reputable organization, (3) have a compatible license. As of this writing, no such need exists.

## 10. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Multi-module package (FitCheckCore, FitCheckOllama, etc.) | Premature complexity. A single module keeps `import FitCheck` simple. Modules can be split later if the API surface grows significantly. |
| Use SwiftLog instead of os.Logger | SwiftLog adds a dependency and an abstraction layer. os.Logger integrates with macOS diagnostic tools natively and has zero overhead when logs are not collected. |
| Support iOS/iPadOS | Local model inference on iOS is constrained by memory limits (6–8 GB total, shared with system). The value proposition of "check what fits" is significantly weaker. macOS-only keeps the scope focused. |
| Support Intel Macs | Intel Macs lack unified memory architecture and Neural Engine, making local LLM inference impractical. Supporting them would add complexity for a use case that delivers a poor user experience. Apple Silicon only. |
| Per-subsystem error enums | Adds catch complexity for consumers who need to handle errors from multiple subsystems in a single call chain. One enum, one catch. |
| Class-based architecture with singletons | Singletons are hostile to testing and concurrency. Protocol + struct/actor pattern allows full injection and isolation. |

## 11. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | What is the minimum macOS version? | **macOS 14 (Sonoma).** Covers all Apple Silicon Macs with current security updates. Enables Metal 3, modern Swift concurrency runtime, and `ProcessInfo` memory pressure APIs. |
| 2 | Single module or multiple modules? | **Single module.** Consumers write `import FitCheck` and get everything. Internal organization uses directories, not module boundaries. Revisit if API surface exceeds 50 public types. |
| 3 | Actor or class for the main entry point? | **Actor.** The `FitCheck` type holds mutable cached state (hardware profile, catalog). An actor provides data-race safety without manual locking, and Swift 6 strict concurrency validates correctness at compile time. |
| 4 | How to handle platform gating? | **Compile-time `#if os(macOS)` plus runtime `.unsupportedPlatform` error.** The package compiles only on macOS. If someone conditionally includes it on another platform, runtime detection provides a clear diagnostic. |
| 5 | External dependencies allowed? | **No, zero dependencies at launch.** System frameworks cover all needs. The dependency policy (§9) defines the bar for future exceptions. |
