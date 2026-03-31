import Foundation

public protocol DownloadProvider: Sendable {
    var name: String { get }
    var providerType: DownloadProviderType { get }
    var installationURL: URL { get }

    func detectInstallation() async throws -> ProviderInstallation
    func downloadAction(for variant: ModelVariant, of card: ModelCard) -> DownloadAction?
    func installedModels() async throws -> [InstalledModel]
}

public enum DownloadProviderType: String, Sendable, Codable, CaseIterable {
    case ollama
    case lmStudio = "lm_studio"
    case mlx

    public var displayName: String {
        switch self {
        case .ollama:   "Ollama"
        case .lmStudio: "LM Studio"
        case .mlx:      "MLX"
        }
    }
}

public struct ProviderInstallation: Sendable, Equatable {
    public let status: InstallationStatus
    public let version: String?
    public let executablePath: String?

    public init(status: InstallationStatus, version: String?, executablePath: String?) {
        self.status = status
        self.version = version
        self.executablePath = executablePath
    }

    public var isInstalled: Bool {
        if case .installed = status { return true }
        return false
    }
}

public enum InstallationStatus: Sendable, Equatable {
    case installed
    case notInstalled
    case error(String)
}

public struct InstalledModel: Sendable, Equatable {
    public let name: String
    public let tag: String?
    public let sizeBytes: UInt64?
    public let modifiedAt: String?
    public let providerType: DownloadProviderType

    public init(name: String, tag: String?, sizeBytes: UInt64?, modifiedAt: String?, providerType: DownloadProviderType) {
        self.name = name
        self.tag = tag
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.providerType = providerType
    }
}
