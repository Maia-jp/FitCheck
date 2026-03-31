import Foundation

public struct MLXProvider: DownloadProvider, Sendable {
    public let name = "MLX"
    public let providerType = DownloadProviderType.mlx
    public let installationURL = URL(string: "https://github.com/ml-explore/mlx-lm")!

    private let shell: any ShellExecutor

    public init(shell: any ShellExecutor = ProcessShellExecutor()) {
        self.shell = shell
    }

    public func detectInstallation() async throws -> ProviderInstallation {
        let checkCommand = ShellCommand(
            executable: "/usr/bin/python3",
            arguments: ["-c", "import mlx_lm; print(mlx_lm.__version__)"]
        )

        let result: ShellResult
        do {
            result = try await shell.run(checkCommand)
        } catch {
            return ProviderInstallation(status: .notInstalled, version: nil, executablePath: nil)
        }

        guard result.succeeded else {
            return ProviderInstallation(status: .notInstalled, version: nil, executablePath: nil)
        }

        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let pythonPath = await shell.which("python3")

        return ProviderInstallation(
            status: .installed,
            version: version.isEmpty ? nil : version,
            executablePath: pythonPath
        )
    }

    public func downloadAction(for variant: ModelVariant, of card: ModelCard) -> DownloadAction? {
        if let mlxID = variant.mlxModelID {
            let command = ShellCommand(
                executable: "python3",
                arguments: ["-m", "mlx_lm", "download", "--model", mlxID]
            )
            return DownloadAction(
                providerType: .mlx,
                method: .shellCommand(command),
                displayInstructions: "python3 -m mlx_lm download --model \(mlxID)"
            )
        }

        if let hfURL = card.huggingFaceURL {
            return DownloadAction(
                providerType: .mlx,
                method: .openURL(hfURL),
                displayInstructions: "Browse MLX models: \(hfURL.absoluteString)"
            )
        }

        return nil
    }

    public func installedModels() async throws -> [InstalledModel] {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")

        guard FileManager.default.fileExists(atPath: cacheDir.path) else {
            return []
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: nil
            )
            return contents
                .filter { $0.lastPathComponent.hasPrefix("models--mlx-community") }
                .map { dir in
                    let modelName = dir.lastPathComponent
                        .replacingOccurrences(of: "models--", with: "")
                        .replacingOccurrences(of: "--", with: "/")
                    return InstalledModel(
                        name: modelName,
                        tag: nil,
                        sizeBytes: nil,
                        modifiedAt: nil,
                        providerType: .mlx
                    )
                }
        } catch {
            Log.providers.error("Failed to list MLX models: \(error)")
            return []
        }
    }
}
