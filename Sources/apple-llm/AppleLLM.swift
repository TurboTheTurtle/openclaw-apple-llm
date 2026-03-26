import ArgumentParser
import Foundation
import FoundationModels

@main
struct AppleLLM: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apple-llm",
        abstract: "Bridge Apple Foundation Models to stdin/stdout",
        version: "0.1.0"
    )

    @Option(name: .long, help: "Prompt text (alternative to stdin)")
    var prompt: String?

    @Option(name: .long, help: "System instructions for the model")
    var system: String?

    @Option(name: .long, help: "Maximum response tokens")
    var maxTokens: Int?

    @Option(name: .long, help: "Sampling temperature (0.0-2.0)")
    var temperature: Double?

    @Flag(name: .long, help: "JSON input/output mode")
    var json = false

    @Flag(name: .long, help: "Disable streaming (buffer full response)")
    var noStream = false

    func run() async throws {
        // Disable stdout buffering for streaming
        setbuf(stdout, nil)

        do {
            try ModelBridge.ensureAvailable()

            let (resolvedPrompt, resolvedSystem, resolvedMaxTokens, resolvedTemperature) = try resolveInput()

            let finalSystem = system ?? resolvedSystem
            let finalMaxTokens = maxTokens ?? resolvedMaxTokens
            let finalTemperature = temperature ?? resolvedTemperature
            let opts = ModelBridge.makeOptions(maxTokens: finalMaxTokens, temperature: finalTemperature)

            if noStream || json {
                let content = try await ModelBridge.generate(
                    prompt: resolvedPrompt,
                    system: finalSystem,
                    options: opts
                )
                if json {
                    let output = JSONOutput(content: content)
                    let data = try output.toJSON()
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                } else {
                    print(content)
                }
            } else {
                try await ModelBridge.generateStream(
                    prompt: resolvedPrompt,
                    system: finalSystem,
                    options: opts
                ) { delta in
                    FileHandle.standardOutput.write(Data(delta.utf8))
                }
                // Final newline after streaming
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } catch let error as LanguageModelSession.GenerationError {
            writeError(BridgeError.fromGeneration(error))
            throw ExitCode(1)
        } catch let error as BridgeError {
            writeError(error.localizedDescription)
            throw ExitCode(1)
        } catch {
            writeError(error.localizedDescription)
            throw ExitCode(1)
        }
    }

    private func resolveInput() throws -> (prompt: String, system: String?, maxTokens: Int?, temperature: Double?) {
        if json {
            let input = try readJSONInput()
            let prompt = input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { throw BridgeError.emptyPrompt }
            return (prompt, input.system, input.max_tokens, input.temperature)
        }

        if let prompt = self.prompt {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw BridgeError.emptyPrompt }
            return (trimmed, nil, nil, nil)
        }

        // Read from stdin if piped
        guard isatty(STDIN_FILENO) == 0 else {
            throw BridgeError.emptyPrompt
        }

        let stdinText = readAllStdin().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdinText.isEmpty else { throw BridgeError.emptyPrompt }
        return (stdinText, nil, nil, nil)
    }

    private func readJSONInput() throws -> JSONInput {
        let data: Data
        if let promptFlag = self.prompt {
            // --json --prompt means the prompt flag is the JSON
            data = Data(promptFlag.utf8)
        } else {
            guard isatty(STDIN_FILENO) == 0 else {
                throw BridgeError.invalidJSON("No JSON input. Pipe JSON to stdin or use --prompt with JSON string.")
            }
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        do {
            return try JSONDecoder().decode(JSONInput.self, from: data)
        } catch {
            throw BridgeError.invalidJSON(error.localizedDescription)
        }
    }

    private func readAllStdin() -> String {
        String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func writeError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}
