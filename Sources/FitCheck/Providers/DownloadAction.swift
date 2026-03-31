import Foundation

public struct DownloadAction: Sendable, Equatable {
    public let providerType: DownloadProviderType
    public let method: DownloadMethod
    public let displayInstructions: String

    public init(providerType: DownloadProviderType, method: DownloadMethod, displayInstructions: String) {
        self.providerType = providerType
        self.method = method
        self.displayInstructions = displayInstructions
    }

    public var shellCommand: ShellCommand? {
        if case .shellCommand(let cmd) = method { return cmd }
        return nil
    }

    public var url: URL? {
        if case .openURL(let url) = method { return url }
        return nil
    }
}

public enum DownloadMethod: Sendable, Equatable {
    case shellCommand(ShellCommand)
    case openURL(URL)
}
