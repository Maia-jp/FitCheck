import Foundation
import Testing
@testable import FitCheck

// MARK: - MockShellExecutor

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

// MARK: - OllamaProvider tests

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

// MARK: - LMStudioProvider tests

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

    @Test("Returns nil when no model ID and no URLs")
    func noIdentifiers() {
        let variant = ModelVariant.fixture(ollamaTag: nil, lmStudioModelID: nil)
        let card = ModelCard.fixture()
        let provider = LMStudioProvider()
        let action = provider.downloadAction(for: variant, of: card)

        #expect(action == nil)
    }
}

// MARK: - ShellCommand tests

@Suite("ShellCommand")
struct ShellCommandTests {
    @Test("fullCommand quotes arguments with spaces")
    func quoting() {
        let cmd = ShellCommand(executable: "/usr/bin/env", arguments: ["hello world", "foo"])
        #expect(cmd.fullCommand == "/usr/bin/env \"hello world\" foo")
    }
}
