import Foundation

public struct LMStudioProvider: DownloadProvider, Sendable {
    public let name = "LM Studio"
    public let providerType = DownloadProviderType.lmStudio
    public let installationURL = URL(string: "https://lmstudio.ai")!

    private let shell: any ShellExecutor
    private let appPath: String

    public init(
        shell: any ShellExecutor = ProcessShellExecutor(),
        appPath: String = "/Applications/LM Studio.app"
    ) {
        self.shell = shell
        self.appPath = appPath
    }

    public func detectInstallation() async throws -> ProviderInstallation {
        let appExists = FileManager.default.fileExists(atPath: appPath)
        let cliPath = await shell.which("lms")

        if !appExists && cliPath == nil {
            return ProviderInstallation(status: .notInstalled, version: nil, executablePath: nil)
        }

        var version: String?
        if let cli = cliPath {
            let versionCommand = ShellCommand(executable: cli, arguments: ["version"])
            if let result = try? await shell.run(versionCommand), result.succeeded {
                version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ProviderInstallation(
            status: .installed,
            version: version,
            executablePath: cliPath ?? appPath
        )
    }

    public func downloadAction(for variant: ModelVariant, of card: ModelCard) -> DownloadAction? {
        if let modelID = variant.lmStudioModelID {
            let command = ShellCommand(executable: "lms", arguments: ["get", modelID])
            return DownloadAction(
                providerType: .lmStudio,
                method: .shellCommand(command),
                displayInstructions: "lms get \(modelID)"
            )
        }

        if let downloadURL = variant.downloadURL ?? card.huggingFaceURL {
            return DownloadAction(
                providerType: .lmStudio,
                method: .openURL(downloadURL),
                displayInstructions: "Open in LM Studio: \(downloadURL.absoluteString)"
            )
        }

        return nil
    }

    public func installedModels() async throws -> [InstalledModel] {
        guard let cliPath = await shell.which("lms") else {
            return []
        }

        let command = ShellCommand(executable: cliPath, arguments: ["ls"])
        let result: ShellResult
        do {
            result = try await shell.run(command)
        } catch {
            Log.providers.error("Failed to list LM Studio models: \(error)")
            return []
        }

        guard result.succeeded else {
            Log.providers.error("lms ls exited with code \(result.exitCode)")
            return []
        }

        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { InstalledModel(name: $0, tag: nil, sizeBytes: nil, modifiedAt: nil, providerType: .lmStudio) }
    }
}
