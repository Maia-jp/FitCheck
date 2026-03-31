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

    // MARK: - sysctl

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
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
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
        guard case .appleSilicon(let variant) = chip else { return 0 }
        return Self.knownGPUCores[variant] ?? 0
    }

    private static let knownGPUCores: [AppleSiliconVariant: Int] = [
        .m1: 8,  .m1Pro: 16, .m1Max: 32, .m1Ultra: 64,
        .m2: 10, .m2Pro: 19, .m2Max: 38, .m2Ultra: 76,
        .m3: 10, .m3Pro: 18, .m3Max: 40, .m3Ultra: 80,
        .m4: 10, .m4Pro: 20, .m4Max: 40, .m4Ultra: 80,
    ]

    // MARK: - Neural Engine

    private func resolveNeuralEngineCoreCount(chip: Chip) -> Int {
        guard case .appleSilicon(let variant) = chip else { return 0 }
        return Self.knownNeuralEngineCores[variant] ?? 0
    }

    private static let knownNeuralEngineCores: [AppleSiliconVariant: Int] = [
        .m1: 16, .m1Pro: 16, .m1Max: 16, .m1Ultra: 32,
        .m2: 16, .m2Pro: 16, .m2Max: 16, .m2Ultra: 32,
        .m3: 16, .m3Pro: 16, .m3Max: 16, .m3Ultra: 32,
        .m4: 16, .m4Pro: 16, .m4Max: 16, .m4Ultra: 32,
    ]
}
