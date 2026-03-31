# RFC-005: Download Provider Integration

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Draft                                       |
| Created     | 2026-03-31                                  |
| Depends on  | RFC-001, RFC-003                            |
| Phase       | 2                                           |

---

## 1. Motivation

Knowing which models fit on a user's Mac is useful. Being able to download those models immediately is transformative. Two dominant tools exist for running models locally on macOS: Ollama (CLI-driven, developer-oriented) and LM Studio (GUI-driven, accessible). Each has its own model naming scheme, installation path, and download mechanism.

This RFC defines a `DownloadProvider` protocol that abstracts the detection, installation checking, and download action generation for any local inference runtime. It provides concrete implementations for `OllamaProvider` and `LMStudioProvider`, and a `ShellExecutor` protocol for testable shell command execution.

## 2. Provider Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                  DownloadProvider                      │
│                    (protocol)                          │
└───────┬──────────────────────────────────┬────────────┘
        │                                  │
        ▼                                  ▼
┌───────────────────┐         ┌─────────────────────┐
│  OllamaProvider   │         │  LMStudioProvider   │
│                   │         │                     │
│  Detection:       │         │  Detection:         │
│   which ollama    │         │   /Applications/    │
│                   │         │   LM Studio.app     │
│  Download:        │         │   + which lms       │
│   ollama pull     │         │                     │
│   <tag>           │         │  Download:          │
│                   │         │   lms get <id>      │
│  List installed:  │         │   or open URL       │
│   ollama list     │         │                     │
└────────┬──────────┘         └──────────┬──────────┘
         │                               │
         └──────────────┬────────────────┘
                        ▼
              ┌──────────────────┐
              │  ShellExecutor   │
              │   (protocol)     │
              │                  │
              │  Concrete:       │
              │  ProcessShell    │
              │  Executor        │
              └──────────────────┘
```

Both providers use `ShellExecutor` for all system interaction. In production, `ProcessShellExecutor` runs real shell commands via `Foundation.Process`. In tests, `MockShellExecutor` returns scripted responses.

## 3. Data Model

### 3.1 DownloadProvider Protocol

```swift
// Sources/FitCheck/Providers/DownloadProvider.swift  [new file]

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

    public var displayName: String {
        switch self {
        case .ollama:   return "Ollama"
        case .lmStudio: return "LM Studio"
        }
    }
}
```

### 3.2 ProviderInstallation

```swift
// Inside DownloadProvider.swift

public struct ProviderInstallation: Sendable, Equatable {
    public let status: InstallationStatus
    public let version: String?
    public let executablePath: String?

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
```

### 3.3 DownloadAction

A `DownloadAction` tells the consumer how to obtain a model through a given provider. It may be a shell command (Ollama pull), a CLI command (LM Studio), or a URL to open.

```swift
// Sources/FitCheck/Providers/DownloadAction.swift  [new file]

public struct DownloadAction: Sendable, Equatable {
    public let providerType: DownloadProviderType
    public let method: DownloadMethod
    public let displayInstructions: String

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

public struct ShellCommand: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]

    public var fullCommand: String {
        ([executable] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }
}
```

### 3.4 InstalledModel

```swift
// Inside DownloadProvider.swift

public struct InstalledModel: Sendable, Equatable {
    public let name: String
    public let tag: String?
    public let sizeBytes: UInt64?
    public let modifiedAt: String?
    public let providerType: DownloadProviderType
}
```

## 4. Shell Executor

### 4.1 Protocol

```swift
// Sources/FitCheck/Providers/ShellExecutor.swift  [new file]

import Foundation

public protocol ShellExecutor: Sendable {
    func run(_ command: ShellCommand) async throws -> ShellResult
    func which(_ executable: String) async -> String?
}

public struct ShellResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}
```

### 4.2 ProcessShellExecutor

```swift
// Inside ShellExecutor.swift

public struct ProcessShellExecutor: ShellExecutor, Sendable {
    public init() {}

    public func run(_ command: ShellCommand) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw FitCheckError.shellCommandFailed(
                command: command.fullCommand,
                exitCode: -1,
                stderr: error.localizedDescription
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    public func which(_ executable: String) async -> String? {
        let command = ShellCommand(executable: "/usr/bin/which", arguments: [executable])
        guard let result = try? await run(command),
              result.succeeded else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

## 5. Ollama Provider

### 5.1 Implementation

```swift
// Sources/FitCheck/Providers/OllamaProvider.swift  [new file]

import Foundation

public struct OllamaProvider: DownloadProvider, Sendable {
    public let name = "Ollama"
    public let providerType = DownloadProviderType.ollama
    public let installationURL = URL(string: "https://ollama.com/download")!

    private let shell: any ShellExecutor

    public init(shell: any ShellExecutor = ProcessShellExecutor()) {
        self.shell = shell
    }

    // MARK: - Installation detection

    public func detectInstallation() async throws -> ProviderInstallation {
        guard let path = await shell.which("ollama") else {
            return ProviderInstallation(
                status: .notInstalled,
                version: nil,
                executablePath: nil
            )
        }

        let versionCommand = ShellCommand(
            executable: path,
            arguments: ["--version"]
        )

        let version: String?
        if let result = try? await shell.run(versionCommand), result.succeeded {
            version = parseOllamaVersion(from: result.stdout)
        } else {
            version = nil
        }

        return ProviderInstallation(
            status: .installed,
            version: version,
            executablePath: path
        )
    }

    // MARK: - Download action

    public func downloadAction(
        for variant: ModelVariant,
        of card: ModelCard
    ) -> DownloadAction? {
        guard let tag = variant.ollamaTag else { return nil }

        let command = ShellCommand(
            executable: "/usr/local/bin/ollama",
            arguments: ["pull", tag]
        )

        return DownloadAction(
            providerType: .ollama,
            method: .shellCommand(command),
            displayInstructions: "ollama pull \(tag)"
        )
    }

    // MARK: - Installed models

    public func installedModels() async throws -> [InstalledModel] {
        let installation = try await detectInstallation()
        guard installation.isInstalled,
              let path = installation.executablePath else {
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

        return parseOllamaList(result.stdout)
    }

    // MARK: - Parsing

    private func parseOllamaVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let versionPart = trimmed.split(separator: " ").last {
            return String(versionPart)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseOllamaList(_ output: String) -> [InstalledModel] {
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let columns = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            ).map { $0.trimmingCharacters(in: .whitespaces) }

            guard let nameTag = columns.first, !nameTag.isEmpty else {
                return nil
            }

            let parts = nameTag.split(separator: ":", maxSplits: 1)
            let name = String(parts[0])
            let tag = parts.count > 1 ? String(parts[1]) : nil

            let sizeBytes: UInt64? = columns.count > 2
                ? parseHumanSize(columns[2])
                : nil

            let modified: String? = columns.count > 3
                ? columns[3]
                : nil

            return InstalledModel(
                name: name,
                tag: tag,
                sizeBytes: sizeBytes,
                modifiedAt: modified,
                providerType: .ollama
            )
        }
    }

    private func parseHumanSize(_ str: String) -> UInt64? {
        let trimmed = str.trimmingCharacters(in: .whitespaces).uppercased()
        let multipliers: [(String, Double)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1_024),
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
```

### 5.2 Ollama Command Reference

| Operation | Command | Expected Output |
|-----------|---------|----------------|
| Check installed | `which ollama` | Path to binary or exit code 1 |
| Get version | `ollama --version` | `"ollama version 0.X.Y"` |
| Pull model | `ollama pull <tag>` | Progress output, exit code 0 on success |
| List installed | `ollama list` | Tab-separated table: NAME, ID, SIZE, MODIFIED |

## 6. LM Studio Provider

### 6.1 Implementation

```swift
// Sources/FitCheck/Providers/LMStudioProvider.swift  [new file]

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

    // MARK: - Installation detection

    public func detectInstallation() async throws -> ProviderInstallation {
        let appExists = FileManager.default.fileExists(atPath: appPath)
        let cliPath = await shell.which("lms")

        if !appExists && cliPath == nil {
            return ProviderInstallation(
                status: .notInstalled,
                version: nil,
                executablePath: nil
            )
        }

        var version: String?
        if let cli = cliPath {
            let versionCommand = ShellCommand(
                executable: cli,
                arguments: ["version"]
            )
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

    // MARK: - Download action

    public func downloadAction(
        for variant: ModelVariant,
        of card: ModelCard
    ) -> DownloadAction? {
        if let modelID = variant.lmStudioModelID {
            let command = ShellCommand(
                executable: "/usr/local/bin/lms",
                arguments: ["get", modelID]
            )
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

    // MARK: - Installed models

    public func installedModels() async throws -> [InstalledModel] {
        let installation = try await detectInstallation()
        guard installation.isInstalled else { return [] }

        guard let cliPath = await shell.which("lms") else {
            Log.providers.info("LM Studio installed but CLI (lms) not found — cannot list models")
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

        return parseLMStudioList(result.stdout)
    }

    // MARK: - Parsing

    private func parseLMStudioList(_ output: String) -> [InstalledModel] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                InstalledModel(
                    name: line,
                    tag: nil,
                    sizeBytes: nil,
                    modifiedAt: nil,
                    providerType: .lmStudio
                )
            }
    }
}
```

### 6.2 LM Studio Command Reference

| Operation | Command / Check | Expected Output |
|-----------|----------------|----------------|
| Check app installed | `FileManager.fileExists(atPath: "/Applications/LM Studio.app")` | `true` / `false` |
| Check CLI installed | `which lms` | Path to binary or exit code 1 |
| Get version | `lms version` | Version string |
| Download model | `lms get <model-id>` | Progress output |
| List installed | `lms ls` | One model path per line |

### 6.3 LM Studio Download Fallback

When a `ModelVariant` has no `lmStudioModelID` but has a `downloadURL` or the parent `ModelCard` has a `huggingFaceURL`, the provider generates an `openURL` action. The consumer can use `NSWorkspace.shared.open(url)` to open the URL in LM Studio or the default browser.

## 7. Error Handling

| Scenario | Detection | Recovery |
|----------|-----------|---------|
| Provider binary not found | `which` returns `nil` | Return `ProviderInstallation(status: .notInstalled, ...)`. The consumer can display installation instructions with `installationURL`. |
| Provider binary found but version command fails | `shell.run()` returns non-zero exit code | Return `ProviderInstallation(status: .installed, version: nil, ...)`. Version is optional — the provider is still usable. |
| `ollama pull` fails mid-download | Consumer detects non-zero exit code from shell | Not handled by FitCheck directly. The `DownloadAction` contains the command; execution responsibility belongs to the consumer. FitCheck generates the action, not executes it. |
| No Ollama tag for variant | `variant.ollamaTag` is `nil` | `downloadAction` returns `nil`. The consumer skips this provider for this variant. |
| No LM Studio ID or download URL | Both fields are `nil` | `downloadAction` returns `nil`. Same handling as above. |
| Shell execution throws | `Process.run()` throws | Throw `FitCheckError.shellCommandFailed(...)` from `ProcessShellExecutor`. Callers catch and log. |
| `ollama list` output format changes | Parsing produces zero results | Return empty `[InstalledModel]`. Logged at `.error` level. |

## 8. Testing Strategy

### 8.1 MockShellExecutor

```swift
// Tests/FitCheckTests/Providers/MockShellExecutor.swift

actor MockShellExecutor: ShellExecutor {
    private var responses: [String: ShellResult] = [:]
    private var whichResults: [String: String?] = [:]

    func setResponse(for executable: String, result: ShellResult) {
        responses[executable] = result
    }

    func setWhichResult(for name: String, path: String?) {
        whichResults[name] = path
    }

    func run(_ command: ShellCommand) throws -> ShellResult {
        responses[command.executable] ?? ShellResult(exitCode: 0, stdout: "", stderr: "")
    }

    func which(_ executable: String) -> String? {
        whichResults[executable] ?? nil
    }
}
```

Actor-isolated methods implicitly satisfy `async` protocol requirements — callers `await` the actor hop. The methods themselves are synchronous within the actor's isolation domain.

### 8.2 Unit Tests

```swift
// Tests/FitCheckTests/Providers/OllamaProviderTests.swift

import Testing
@testable import FitCheck

@Suite("OllamaProvider")
struct OllamaProviderTests {
    @Test("Detects installed Ollama")
    func detectInstalled() async throws {
        let shell = MockShellExecutor()
        await shell.setWhichResult(for: "ollama", path: "/usr/local/bin/ollama")
        await shell.setResponse(
            for: "/usr/local/bin/ollama",
            result: ShellResult(exitCode: 0, stdout: "ollama version 0.5.4", stderr: "")
        )

        let provider = OllamaProvider(shell: shell)
        let installation = try await provider.detectInstallation()

        #expect(installation.isInstalled)
        #expect(installation.version == "0.5.4")
    }

    @Test("Detects missing Ollama")
    func detectNotInstalled() async throws {
        let shell = MockShellExecutor()
        await shell.setWhichResult(for: "ollama", path: nil)

        let provider = OllamaProvider(shell: shell)
        let installation = try await provider.detectInstallation()

        #expect(!installation.isInstalled)
    }

    @Test("Generates correct download action for variant with Ollama tag")
    func downloadAction() {
        let variant = ModelVariant.fixture(ollamaTag: "llama3.1:8b-instruct-q4_K_M")
        let card = ModelCard.fixture()
        let provider = OllamaProvider()
        let action = provider.downloadAction(for: variant, of: card)

        #expect(action != nil)
        #expect(action?.displayInstructions == "ollama pull llama3.1:8b-instruct-q4_K_M")
    }

    @Test("Returns nil download action when no Ollama tag")
    func noTag() {
        let variant = ModelVariant.fixture(ollamaTag: nil)
        let card = ModelCard.fixture()
        let provider = OllamaProvider()
        let action = provider.downloadAction(for: variant, of: card)

        #expect(action == nil)
    }
}

// Tests/FitCheckTests/Providers/LMStudioProviderTests.swift

@Suite("LMStudioProvider")
struct LMStudioProviderTests {
    @Test("Generates CLI download action when model ID available")
    func cliDownload() {
        let variant = ModelVariant.fixture(
            lmStudioModelID: "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF"
        )
        let card = ModelCard.fixture()
        let provider = LMStudioProvider()
        let action = provider.downloadAction(for: variant, of: card)

        #expect(action != nil)
        #expect(action?.shellCommand != nil)
        #expect(action?.displayInstructions.contains("lms get") == true)
    }

    @Test("Falls back to URL when no model ID")
    func urlFallback() {
        let variant = ModelVariant.fixture(lmStudioModelID: nil)
        let card = ModelCard.fixture()
        let provider = LMStudioProvider()
        let action = provider.downloadAction(for: variant, of: card)

        if card.huggingFaceURL != nil {
            #expect(action?.url != nil)
        }
    }
}
```

## 9. Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Execute downloads directly within FitCheck | FitCheck is a library, not an application. Downloading models can take minutes to hours. Owning that lifecycle (progress, cancellation, retry) is a massive scope expansion. Instead, FitCheck generates `DownloadAction` values — the consumer decides when and how to execute them. |
| Support `llama.cpp` as a third provider | llama.cpp is a C++ library, not a model manager. It runs models but does not download them. Ollama (which wraps llama.cpp) and LM Studio handle the download-and-run lifecycle. |
| Use Ollama's HTTP API instead of CLI | Ollama exposes a REST API on `localhost:11434`. However, the API is only available when the Ollama server is running. The CLI works regardless of server state and is simpler for detection and pull operations. |
| Hard-code executable paths | Paths like `/usr/local/bin/ollama` vary by installation method (Homebrew, direct download, custom prefix). `which` resolves the actual path dynamically. Hard-coded paths are used as fallbacks only in `downloadAction` (where they serve as instructions, not execution targets). |
| Make `DownloadProvider` an actor | Providers hold no mutable state. All fields are `let`. The `ShellExecutor` they reference is `Sendable`. Making them actors would add unnecessary isolation overhead. |

## 10. Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Should FitCheck execute downloads or just generate actions? | **Generate actions only.** `DownloadAction` contains the command string and/or URL. The consumer executes it in their own context, handling progress, cancellation, and UI. This keeps FitCheck a pure query library. |
| 2 | How to detect Ollama installation? | **`which ollama`** via `ShellExecutor`. Cross-platform within macOS, works regardless of how Ollama was installed (Homebrew, direct download, etc.). |
| 3 | How to detect LM Studio installation? | **Two checks: `FileManager.fileExists` for the `.app` bundle, and `which lms` for the CLI.** The app can exist without the CLI (user never set it up). Both are checked independently. |
| 4 | How to handle providers that aren't installed? | **Return `ProviderInstallation(status: .notInstalled, ...)` with the provider's `installationURL`.** The consumer can display a prompt: "Ollama is not installed. Get it at https://ollama.com/download". No error is thrown — a missing provider is a normal state, not an error. |
| 5 | How to abstract shell execution for testing? | **`ShellExecutor` protocol with `ProcessShellExecutor` (production) and `MockShellExecutor` (tests).** Injected via initializer. Every provider method that touches the shell goes through this protocol. |
| 6 | What if a variant has no tag/ID for a provider? | **`downloadAction` returns `nil`.** The consumer checks which providers have actions for a variant and presents only the available options. This is expected — not every model is available on every provider. |
