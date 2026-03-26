import Foundation
import FoundationModels

enum BridgeError: LocalizedError {
    case notEnabled
    case notEligible
    case notReady
    case unavailable
    case emptyPrompt
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .notEnabled:
            "Apple Intelligence is not enabled. Enable it in System Settings > Apple Intelligence & Siri."
        case .notEligible:
            "This device does not support Apple Foundation Models."
        case .notReady:
            "Model is not ready. It may still be downloading. Try again shortly."
        case .unavailable:
            "Foundation model is unavailable."
        case .emptyPrompt:
            "No prompt provided. Use --prompt, pipe to stdin, or use --json mode."
        case .invalidJSON(let detail):
            "Invalid JSON input: \(detail)"
        }
    }
}

struct ModelBridge: Sendable {

    static func ensureAvailable() throws {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return
        case .unavailable(.appleIntelligenceNotEnabled):
            throw BridgeError.notEnabled
        case .unavailable(.deviceNotEligible):
            throw BridgeError.notEligible
        case .unavailable(.modelNotReady):
            throw BridgeError.notReady
        @unknown default:
            throw BridgeError.unavailable
        }
    }

    static func generate(
        prompt: String,
        system: String?,
        options: GenerationOptions?
    ) async throws -> String {
        let session = makeSession(system: system)
        let response: LanguageModelSession.Response<String>
        if let options {
            response = try await session.respond(to: prompt, options: options)
        } else {
            response = try await session.respond(to: prompt)
        }
        return response.content
    }

    static func generateStream(
        prompt: String,
        system: String?,
        options: GenerationOptions?,
        onPartial: @Sendable (String) -> Void
    ) async throws {
        let session = makeSession(system: system)
        let stream: LanguageModelSession.ResponseStream<String>
        if let options {
            stream = session.streamResponse(to: prompt, options: options)
        } else {
            stream = session.streamResponse(to: prompt)
        }
        var emittedUpTo = "".startIndex
        for try await partial in stream {
            let content = partial.content
            if content.endIndex > emittedUpTo {
                let newText = String(content[emittedUpTo...])
                emittedUpTo = content.endIndex
                onPartial(newText)
            }
        }
    }

    static func makeOptions(maxTokens: Int?, temperature: Double?) -> GenerationOptions? {
        guard maxTokens != nil || temperature != nil else { return nil }
        var opts = GenerationOptions()
        if let maxTokens {
            opts.maximumResponseTokens = maxTokens
        }
        if let temperature {
            opts.temperature = temperature
        }
        return opts
    }

    private static func makeSession(system: String?) -> LanguageModelSession {
        if let system {
            return LanguageModelSession(instructions: system)
        } else {
            return LanguageModelSession()
        }
    }
}

extension BridgeError {
    static func fromGeneration(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            "Prompt exceeds context window. Reduce input length."
        case .rateLimited:
            "Rate limited. Wait and retry."
        case .guardrailViolation:
            "Request was blocked by content guardrails."
        case .refusal:
            "Model refused the request."
        case .assetsUnavailable:
            "Model assets unavailable. Ensure Apple Intelligence is set up."
        case .decodingFailure:
            "Internal decoding failure."
        case .unsupportedGuide:
            "Unsupported generation guide."
        case .unsupportedLanguageOrLocale:
            "Unsupported language or locale."
        case .concurrentRequests:
            "Too many concurrent requests. Try again."
        @unknown default:
            "Generation error: \(error.localizedDescription)"
        }
    }
}
