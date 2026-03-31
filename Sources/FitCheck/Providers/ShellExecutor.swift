import Foundation

public protocol ShellExecutor: Sendable {
    func run(_ command: ShellCommand) async throws -> ShellResult
    func which(_ executable: String) async -> String?
}

public struct ShellCommand: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var fullCommand: String {
        ([executable] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }
}

public struct ShellResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

// MARK: - ProcessShellExecutor

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
        guard let result = try? await run(command), result.succeeded else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
