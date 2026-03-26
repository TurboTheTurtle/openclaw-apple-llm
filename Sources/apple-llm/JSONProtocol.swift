import Foundation

struct JSONInput: Sendable, Codable {
    let prompt: String
    var system: String?
    var max_tokens: Int?
    var temperature: Double?
}

struct JSONOutput: Sendable, Encodable {
    let content: String
    let tokensUsed: Int?

    static let modelIdentifier = "apple-foundation"

    init(content: String, tokensUsed: Int? = nil) {
        self.content = content
        self.tokensUsed = tokensUsed
    }

    enum CodingKeys: String, CodingKey {
        case content
        case model
        case tokens_used
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        try container.encode(Self.modelIdentifier, forKey: .model)
        try container.encode(tokensUsed, forKey: .tokens_used)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func toJSON() throws -> Data {
        try Self.encoder.encode(self)
    }
}
