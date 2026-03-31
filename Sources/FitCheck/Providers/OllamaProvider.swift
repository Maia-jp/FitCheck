import Foundation

public struct OllamaProvider: DownloadProvider, Sendable {
    public let name = "Ollama"
    public let providerType = DownloadProviderType.ollama
    public let installationURL = URL(string: "https://ollama.com/download")!

    private let shell: any ShellExecutor

    public init(shell: any ShellExecutor = ProcessShellExecutor()) {
        self.shell = shell
    }

    public func detectInstallation() async throws -> ProviderInstallation {
        guard let path = await shell.which("ollama") else {
            return ProviderInstallation(status: .notInstalled, version: nil, executablePath: nil)
        }

        let versionCommand = ShellCommand(executable: path, arguments: ["--version"])
        let version: String?
        if let result = try? await shell.run(versionCommand), result.succeeded {
            version = parseVersion(from: result.stdout)
        } else {
            version = nil
        }

        return ProviderInstallation(status: .installed, version: version, executablePath: path)
    }

    public func downloadAction(for variant: ModelVariant, of card: ModelCard) -> DownloadAction? {
        guard let tag = variant.ollamaTag else { return nil }
        let command = ShellCommand(executable: "ollama", arguments: ["pull", tag])
        return DownloadAction(
            providerType: .ollama,
            method: .shellCommand(command),
            displayInstructions: "ollama pull \(tag)"
        )
    }

    public func installedModels() async throws -> [InstalledModel] {
        let installation = try await detectInstallation()
        guard installation.isInstalled, let path = installation.executablePath else {
            return []
        }

        let command = ShellCommand(executable: path, arguments: ["list"])
        let result: ShellResult
        do {
            result = try await shell.run(command)
        } catch {
            Log.providers.error("Failed to list Ollama models: \(error)")
            return []
        }

        guard result.succeeded else {
            Log.providers.error("ollama list exited with code \(result.exitCode)")
            return []
        }

        return parseModelList(result.stdout)
    }

    // MARK: - Parsing

    private func parseVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let versionPart = trimmed.split(separator: " ").last {
            return String(versionPart)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseModelList(_ output: String) -> [InstalledModel] {
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let nameTag = columns.first, !nameTag.isEmpty else { return nil }

            let parts = nameTag.split(separator: ":", maxSplits: 1)
            let name = String(parts[0])
            let tag = parts.count > 1 ? String(parts[1]) : nil
            let sizeBytes: UInt64? = columns.count > 2 ? parseHumanSize(columns[2]) : nil
            let modified: String? = columns.count > 3 ? columns[3] : nil

            return InstalledModel(
                name: name, tag: tag, sizeBytes: sizeBytes,
                modifiedAt: modified, providerType: .ollama
            )
        }
    }

    private func parseHumanSize(_ str: String) -> UInt64? {
        let trimmed = str.trimmingCharacters(in: .whitespaces).uppercased()
        let multipliers: [(String, Double)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824),
            ("MB", 1_048_576), ("KB", 1_024),
        ]
        for (suffix, multiplier) in multipliers {
            if trimmed.hasSuffix(suffix),
               let value = Double(trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) {
                return UInt64(value * multiplier)
            }
        }
        return UInt64(trimmed)
    }
}
