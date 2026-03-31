# RFC-002: Hardware Profiling

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | RFC-001                                     |
| Phase       | 1                                           |

---

## 1. Motivation

To determine whether a given AI model can run on a user's Mac, FitCheck must first know what hardware is available. Memory capacity, GPU core count, chip generation, and Neural Engine presence all influence which models fit and at what performance tier. macOS provides this information through several disjoint APIs (`sysctl`, `ProcessInfo`, `Metal`, `IOKit`), none of which give a unified picture.

This RFC defines a `HardwareProfile` value type that captures every hardware attribute relevant to local model inference, a `HardwareProfiler` protocol for obtaining that profile, and a `SystemHardwareProfiler` implementation that queries real system APIs.

## 2. Hardware Profiling Overview

```
┌─────────────────────────────────────────────────────┐
│              SystemHardwareProfiler                  │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │  sysctl  │  │ProcessInfo│  │   Metal API      │  │
│  │          │  │          │  │                  │  │
│  │ • chip   │  │ • memory │  │ • GPU cores      │  │
│  │   model  │  │ • OS ver │  │ • GPU families   │  │
│  │ • CPU    │  │          │  │ • max buffer     │  │
│  │   cores  │  │          │  │ • working set    │  │
│  └────┬─────┘  └────┬─────┘  └────────┬─────────┘  │
│       │              │                  │            │
│       └──────────────┼──────────────────┘            │
│                      ▼                               │
│            ┌──────────────────┐                      │
│            │ HardwareProfile  │                      │
│            └──────────────────┘                      │
└─────────────────────────────────────────────────────┘
```

The profiler gathers data from three system sources, combines them into a single `HardwareProfile` struct, and caches the result. Hardware does not change during execution, so the profile is computed once per `FitCheck` session.

## 3. Data Model

### 3.1 HardwareProfile

```swift
// Sources/FitCheck/Hardware/HardwareProfile.swift  [new file]

public struct HardwareProfile: Sendable, Equatable, Codable {
    public let chip: Chip
    public let totalMemoryBytes: UInt64
    public let gpuCoreCount: Int
    public let cpuCoreCount: Int
    public let cpuPerformanceCores: Int
    public let cpuEfficiencyCores: Int
    public let neuralEngineCoreCount: Int
    public let osVersion: OperatingSystemVersion
    public let metalSupport: MetalSupport

    public var totalMemoryGB: Double {
        Double(totalMemoryBytes) / 1_073_741_824
    }

    public var hasNeuralEngine: Bool {
        neuralEngineCoreCount > 0
    }

    public var availableMemoryForInferenceBytes: UInt64 {
        let total = Double(totalMemoryBytes)
        let oneGB = 1_073_741_824.0
        let utilizationFactor = 0.85
        let headroomBytes = 2.0 * oneGB
        let usable = Swift.min(utilizationFactor * total, total - headroomBytes)
        return UInt64(Swift.max(oneGB, usable))
    }
}
```

`OperatingSystemVersion` is `Sendable` and `Codable` in macOS 14+. If conformance is missing, a conditional extension is provided in §4.4.

### 3.2 Chip

```swift
// Sources/FitCheck/Hardware/Chip.swift  [new file]

public enum Chip: Sendable, Equatable, Codable {
    case appleSilicon(AppleSiliconVariant)
    case unknown(String)
}

public enum AppleSiliconVariant: String, Sendable, Codable, CaseIterable {
    case m1
    case m1Pro = "m1_pro"
    case m1Max = "m1_max"
    case m1Ultra = "m1_ultra"
    case m2
    case m2Pro = "m2_pro"
    case m2Max = "m2_max"
    case m2Ultra = "m2_ultra"
    case m3
    case m3Pro = "m3_pro"
    case m3Max = "m3_max"
    case m3Ultra = "m3_ultra"
    case m4
    case m4Pro = "m4_pro"
    case m4Max = "m4_max"
    case m4Ultra = "m4_ultra"

    public var family: ChipFamily {
        switch self {
        case .m1, .m1Pro, .m1Max, .m1Ultra: return .m1
        case .m2, .m2Pro, .m2Max, .m2Ultra: return .m2
        case .m3, .m3Pro, .m3Max, .m3Ultra: return .m3
        case .m4, .m4Pro, .m4Max, .m4Ultra: return .m4
        }
    }

    public var tier: ChipTier {
        switch self {
        case .m1, .m2, .m3, .m4:                         return .base
        case .m1Pro, .m2Pro, .m3Pro, .m4Pro:              return .pro
        case .m1Max, .m2Max, .m3Max, .m4Max:              return .max
        case .m1Ultra, .m2Ultra, .m3Ultra, .m4Ultra:      return .ultra
        }
    }
}

public enum ChipFamily: String, Sendable, Codable, CaseIterable, Comparable {
    case m1, m2, m3, m4

    public static func < (lhs: ChipFamily, rhs: ChipFamily) -> Bool {
        lhs.generationIndex < rhs.generationIndex
    }

    internal var generationIndex: Int {
        switch self {
        case .m1: return 1
        case .m2: return 2
        case .m3: return 3
        case .m4: return 4
        }
    }
}

public enum ChipTier: Int, Sendable, Codable, Comparable, CaseIterable {
    case base = 0
    case pro = 1
    case max = 2
    case ultra = 3

    public static func < (lhs: ChipTier, rhs: ChipTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### 3.3 MetalSupport

```swift
// Sources/FitCheck/Hardware/MetalSupport.swift  [new file]

public struct MetalSupport: Sendable, Equatable, Codable {
    public let isSupported: Bool
    public let maxBufferLengthBytes: UInt64
    public let recommendedMaxWorkingSetSizeBytes: UInt64

    public var maxBufferLengthGB: Double {
        Double(maxBufferLengthBytes) / 1_073_741_824
    }

    public var recommendedMaxWorkingSetSizeGB: Double {
        Double(recommendedMaxWorkingSetSizeBytes) / 1_073_741_824
    }
}
```

## 4. Implementation

### 4.1 HardwareProfiler Protocol

```swift
// Sources/FitCheck/Hardware/HardwareProfiler.swift  [new file]

public protocol HardwareProfiler: Sendable {
    func profile() throws -> HardwareProfile
}
```

The method is synchronous (`throws`, not `async throws`) because all underlying APIs (`sysctl`, `ProcessInfo`, `MTLCreateSystemDefaultDevice`) are synchronous. The caller (the `FitCheck` actor) can wrap the call in a `Task` if needed.

### 4.2 SystemHardwareProfiler

```swift
// Sources/FitCheck/Hardware/SystemHardwareProfiler.swift  [new file]

import Foundation
import Metal

public struct SystemHardwareProfiler: HardwareProfiler, Sendable {
    public init() {}

    public func profile() throws -> HardwareProfile {
        let chipIdentifier = try readSysctl("machdep.cpu.brand_string")
        let chip = try parseChip(from: chipIdentifier)

        let totalMemory = ProcessInfo.processInfo.physicalMemory

        let cpuCoreCount = ProcessInfo.processInfo.processorCount
        let perfCores = try? readSysctlInt("hw.perflevel0.logicalcpu")
        let effCores = try? readSysctlInt("hw.perflevel1.logicalcpu")

        let neuralEngineCores = resolveNeuralEngineCoreCount(chip: chip)
        let metalSupport = queryMetalSupport()
        let gpuCores = queryGPUCoreCount(chip: chip)

        return HardwareProfile(
            chip: chip,
            totalMemoryBytes: totalMemory,
            gpuCoreCount: gpuCores,
            cpuCoreCount: cpuCoreCount,
            cpuPerformanceCores: perfCores ?? cpuCoreCount,
            cpuEfficiencyCores: effCores ?? 0,
            neuralEngineCoreCount: neuralEngineCores,
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            metalSupport: metalSupport
        )
    }

    // MARK: - sysctl helpers

    private func readSysctl(_ name: String) throws -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else {
            throw FitCheckError.hardwareDetectionFailed(
                reason: "sysctlbyname(\(name)) size query failed"
            )
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            throw FitCheckError.hardwareDetectionFailed(
                reason: "sysctlbyname(\(name)) value query failed"
            )
        }
        return String(cString: buffer)
    }

    private func readSysctlInt(_ name: String) throws -> Int {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            throw FitCheckError.hardwareDetectionFailed(
                reason: "sysctlbyname(\(name)) int query failed"
            )
        }
        return value
    }

    // MARK: - Chip parsing

    private func parseChip(from brandString: String) throws -> Chip {
        let normalized = brandString.lowercased()

        let variants: [(String, AppleSiliconVariant)] = [
            ("m4 ultra", .m4Ultra), ("m4 max", .m4Max), ("m4 pro", .m4Pro), ("m4", .m4),
            ("m3 ultra", .m3Ultra), ("m3 max", .m3Max), ("m3 pro", .m3Pro), ("m3", .m3),
            ("m2 ultra", .m2Ultra), ("m2 max", .m2Max), ("m2 pro", .m2Pro), ("m2", .m2),
            ("m1 ultra", .m1Ultra), ("m1 max", .m1Max), ("m1 pro", .m1Pro), ("m1", .m1),
        ]

        for (pattern, variant) in variants {
            if normalized.contains(pattern) {
                return .appleSilicon(variant)
            }
        }

        if normalized.contains("apple") {
            return .unknown(brandString)
        }

        throw FitCheckError.unsupportedPlatform(
            detected: "Intel Mac (\(brandString)). FitCheck requires Apple Silicon."
        )
    }

    // MARK: - Metal

    private func queryMetalSupport() -> MetalSupport {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MetalSupport(
                isSupported: false,
                maxBufferLengthBytes: 0,
                recommendedMaxWorkingSetSizeBytes: 0
            )
        }
        return MetalSupport(
            isSupported: true,
            maxBufferLengthBytes: UInt64(device.maxBufferLength),
            recommendedMaxWorkingSetSizeBytes: device.recommendedMaxWorkingSetSize
        )
    }

    private func queryGPUCoreCount(chip: Chip) -> Int {
        guard case .appleSilicon(let variant) = chip else {
            return 0
        }
        return Self.knownGPUCores[variant] ?? 0
    }

    private static let knownGPUCores: [AppleSiliconVariant: Int] = [
        .m1: 8, .m1Pro: 16, .m1Max: 32, .m1Ultra: 64,
        .m2: 10, .m2Pro: 19, .m2Max: 38, .m2Ultra: 76,
        .m3: 10, .m3Pro: 18, .m3Max: 40, .m3Ultra: 80,
        .m4: 10, .m4Pro: 20, .m4Max: 40, .m4Ultra: 80,
    ]

    // MARK: - Neural Engine

    private func resolveNeuralEngineCoreCount(chip: Chip) -> Int {
        guard case .appleSilicon(let variant) = chip else {
            return 0
        }
        return Self.knownNeuralEngineCores[variant] ?? 0
    }

    private static let knownNeuralEngineCores: [AppleSiliconVariant: Int] = [
        .m1: 16, .m1Pro: 16, .m1Max: 16, .m1Ultra: 32,
        .m2: 16, .m2Pro: 16, .m2Max: 16, .m2Ultra: 32,
        .m3: 16, .m3Pro: 16, .m3Max: 16, .m3Ultra: 32,
        .m4: 16, .m4Pro: 16, .m4Max: 16, .m4Ultra: 32,
    ]
}
```

### 4.3 Chip Detection Algorithm

The `parseChip` method matches against the `machdep.cpu.brand_string` sysctl value. Apple Silicon brand strings follow the pattern `"Apple M<N>[ Pro|Max|Ultra]"`. The matching order is longest-first to prevent `"M4 Ultra"` from matching the `"M4"` pattern.

```
Input: "Apple M3 Max"
  ▼
Normalize: "apple m3 max"
  ▼
Match against variants (longest first):
  "m4 ultra" → no
  "m4 max"   → no
  ...
  "m3 max"   → YES → return .appleSilicon(.m3Max)
```

If no known Apple Silicon pattern matches but the string contains `"apple"`, it returns `.unknown(brandString)` — this handles future Apple Silicon generations not yet in the lookup table. If the string does not contain `"apple"` (i.e., Intel), the method throws `.unsupportedPlatform`. FitCheck is Apple Silicon only.

### 4.4 OperatingSystemVersion Conformance

`OperatingSystemVersion` may lack `Codable` conformance. Provide a conditional extension:

```swift
// Inside HardwareProfile.swift

extension OperatingSystemVersion: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case majorVersion, minorVersion, patchVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            majorVersion: try container.decode(Int.self, forKey: .majorVersion),
            minorVersion: try container.decode(Int.self, forKey: .minorVersion),
            patchVersion: try container.decode(Int.self, forKey: .patchVersion)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(majorVersion, forKey: .majorVersion)
        try container.encode(minorVersion, forKey: .minorVersion)
        try container.encode(patchVersion, forKey: .patchVersion)
    }
}

extension OperatingSystemVersion: @retroactive Equatable {
    public static func == (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        lhs.majorVersion == rhs.majorVersion
            && lhs.minorVersion == rhs.minorVersion
            && lhs.patchVersion == rhs.patchVersion
    }
}

extension OperatingSystemVersion: @retroactive Sendable {}
```

## 5. Testing Strategy

### 5.1 Mock Profiler

Tests for RFC-004 and RFC-006 inject a mock profiler to simulate different hardware configurations:

```swift
// Tests/FitCheckTests/Hardware/MockHardwareProfiler.swift

struct MockHardwareProfiler: HardwareProfiler {
    let result: Result<HardwareProfile, FitCheckError>

    func profile() throws -> HardwareProfile {
        try result.get()
    }
}

extension HardwareProfile {
    static func fixture(
        chip: Chip = .appleSilicon(.m2),
        totalMemoryBytes: UInt64 = 16 * 1_073_741_824,
        gpuCoreCount: Int = 10,
        cpuCoreCount: Int = 8,
        cpuPerformanceCores: Int = 4,
        cpuEfficiencyCores: Int = 4,
        neuralEngineCoreCount: Int = 16,
        metalSupport: MetalSupport = .init(
            isSupported: true,
            maxBufferLengthBytes: 16 * 1_073_741_824,
            recommendedMaxWorkingSetSizeBytes: 14 * 1_073_741_824
        )
    ) -> HardwareProfile {
        HardwareProfile(
            chip: chip,
            totalMemoryBytes: totalMemoryBytes,
            gpuCoreCount: gpuCoreCount,
            cpuCoreCount: cpuCoreCount,
            cpuPerformanceCores: cpuPerformanceCores,
            cpuEfficiencyCores: cpuEfficiencyCores,
            neuralEngineCoreCount: neuralEngineCoreCount,
            osVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
            metalSupport: metalSupport
        )
    }
}
```

### 5.2 Unit Tests

```swift
// Tests/FitCheckTests/Hardware/SystemHardwareProfilerTests.swift

import Testing
@testable import FitCheck

@Suite("HardwareProfile")
struct HardwareProfileTests {
    @Test("Available memory uses utilization formula: min(0.85*total, total-2GB)")
    func availableMemory16GB() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 16 * 1_073_741_824)
        let available = profile.availableMemoryForInferenceBytes
        let expectedGB = min(0.85 * 16, 16 - 2)  // min(13.6, 14) = 13.6 GB
        let expected = UInt64(expectedGB * 1_073_741_824)
        #expect(available == expected)
    }

    @Test("Available memory on 8 GB Mac leaves ~6 GB for inference")
    func availableMemory8GB() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 8 * 1_073_741_824)
        let availableGB = Double(profile.availableMemoryForInferenceBytes) / 1_073_741_824
        #expect(availableGB >= 5.5)
        #expect(availableGB <= 7.0)
    }

    @Test("Available memory floors at 1 GB")
    func availableMemoryFloor() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 2 * 1_073_741_824)
        #expect(profile.availableMemoryForInferenceBytes == 1_073_741_824)
    }

    @Test("hasNeuralEngine returns true for Apple Silicon")
    func neuralEngineDetection() {
        let profile = HardwareProfile.fixture(chip: .appleSilicon(.m3Pro))
        #expect(profile.hasNeuralEngine)
    }

    @Test("Total memory converts to GB correctly")
    func memoryConversion() {
        let profile = HardwareProfile.fixture(totalMemoryBytes: 36 * 1_073_741_824)
        #expect(profile.totalMemoryGB == 36.0)
    }
}

@Suite("ChipTier")
struct ChipTierTests {
    @Test("Tier ordering: base < pro < max < ultra")
    func tierOrdering() {
        #expect(ChipTier.base < .pro)
        #expect(ChipTier.pro < .max)
        #expect(ChipTier.max < .ultra)
    }
}

@Suite("ChipFamily")
struct ChipFamilyTests {
    @Test("Family ordering: m1 < m2 < m3 < m4")
    func familyOrdering() {
        #expect(ChipFamily.m1 < .m2)
        #expect(ChipFamily.m2 < .m3)
        #expect(ChipFamily.m3 < .m4)
    }
}
```

## 6. Error Handling

| Scenario | Detection | Recovery |
|----------|-----------|---------|
| `sysctlbyname` returns nonzero error code | Return value check after C call | Throw `.hardwareDetectionFailed(reason:)` with the sysctl key name. Caller can fall back to a degraded profile. |
| `MTLCreateSystemDefaultDevice()` returns `nil` | `guard let` check | Return `MetalSupport(isSupported: false, ...)`. Profile is still valid — Metal is needed for GPU detail, not for the overall profile. |
| Intel chip detected | Brand string lacks `"apple"` prefix | Throw `.unsupportedPlatform(detected:)`. FitCheck requires Apple Silicon. Intel Macs lack unified memory and Neural Engine, making local LLM inference impractical. |
| Unknown Apple Silicon variant | Contains `"apple"` but no known M-series pattern | Return `.unknown(brandString)`. Profile is valid — handles future chip generations not yet in the lookup table. Compatibility engine (RFC-004) treats unknown chips conservatively. |
| CPU core count sysctl fails | `readSysctlInt` throws | Fall back to `ProcessInfo.processInfo.processorCount` for total core count. Set efficiency cores to 0. |

## 7. Future Extensibility

### 7.1 New Chip Generations

When Apple releases M5, the implementer adds cases to `AppleSiliconVariant`, extends `ChipFamily`, and adds entries to the `knownGPUCores` and `knownNeuralEngineCores` lookup tables. No architectural changes are needed.

### 7.2 Runtime Memory Pressure

A future RFC could extend `HardwareProfile` with a `currentAvailableMemoryBytes` property queried at check time (not cached), enabling the compatibility engine to account for what's actually free right now versus total capacity.

## 8. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Use `IOKit` registry traversal for chip detection | IOKit provides deep hardware tree access but requires C interop, entitlements in sandboxed apps, and parsing untyped dictionaries. `sysctl` provides the chip brand string directly. |
| Query GPU cores via Metal device properties | Metal exposes `maxThreadgroupMemoryLength` and compute capabilities but does not directly expose GPU core count. A lookup table keyed by chip variant is more reliable and simpler. |
| Async profiler protocol | All underlying APIs (`sysctl`, `ProcessInfo`, `MTLCreateSystemDefaultDevice`) are synchronous and fast (<1ms). Adding `async` to the protocol would force unnecessary concurrency overhead at every call site. |
| Support Intel Macs with degraded performance | Intel Macs lack unified memory architecture, Neural Engine, and the memory bandwidth needed for practical LLM inference. Supporting them would add code paths that serve no real user need and dilute the quality of compatibility verdicts. |
| Cache inside the profiler struct | Structs are value types — caching is semantically wrong. Caching belongs to the caller (the `FitCheck` actor, defined in RFC-006), which holds a single `HardwareProfile?` across its lifetime. |

## 9. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | How to detect Apple Silicon variant? | **Parse `machdep.cpu.brand_string` via `sysctlbyname`.** This returns `"Apple M3 Max"` on Apple Silicon. Pattern matching extracts the variant. More reliable than IOKit for this specific need. |
| 2 | How to get GPU core count? | **Lookup table keyed by `AppleSiliconVariant`.** Apple does not expose GPU core count via any runtime API. The table is sourced from Apple's published specs and covers all shipping variants. |
| 3 | How much memory to reserve for system overhead? | **`min(0.85 × total, total - 2 GB)`, floored at 1 GB.** Mirrors the formula used by llm-checker (calibrated against real Ollama workloads). On an 8 GB Mac: 6 GB available. On 16 GB: 13.6 GB. On 64 GB: 54.4 GB. A flat reserve (like 4 GB) is too aggressive on small machines and too generous on large ones. |
| 4 | Should the profiler be sync or async? | **Sync.** All underlying system calls are synchronous and complete in under 1ms. The `HardwareProfiler` protocol uses `throws` without `async`. |
| 5 | How to handle Neural Engine core count? | **Lookup table, same as GPU cores.** No public API exposes Neural Engine core count at runtime. All Apple Silicon chips have 16 cores (32 for Ultra variants) per Apple's published specifications. |
