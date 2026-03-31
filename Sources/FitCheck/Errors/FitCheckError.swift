import Foundation

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
            "Hardware detection failed: \(reason)"
        case .catalogLoadFailed(let underlying):
            "Failed to load model catalog: \(underlying.localizedDescription)"
        case .catalogDecodingFailed(let path, let underlying):
            "Failed to decode catalog at \(path): \(underlying.localizedDescription)"
        case .networkUnavailable(let underlying):
            "Network unavailable: \(underlying.localizedDescription)"
        case .providerNotInstalled(let provider):
            "\(provider) is not installed on this system"
        case .shellCommandFailed(let command, let exitCode, let stderr):
            "Command '\(command)' failed with exit code \(exitCode): \(stderr)"
        case .modelNotFound(let identifier):
            "No model found with identifier '\(identifier)'"
        case .unsupportedPlatform(let detected):
            "Unsupported platform: \(detected). FitCheck requires macOS on Apple Silicon."
        case .resourceMissing(let name):
            "Required resource '\(name)' not found in bundle"
        }
    }
}
