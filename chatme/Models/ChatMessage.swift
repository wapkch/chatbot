import Foundation

struct ChatMessage: Codable, Sendable {
    let role: Role
    let content: MessageContent

    enum Role: String, CaseIterable, Codable, Sendable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
    }

    // MARK: - Content Types
    enum MessageContent: Codable, Sendable {
        case text(String)
        case multipart([ContentPart])

        var stringValue: String {
            switch self {
            case .text(let string):
                return string
            case .multipart(let parts):
                return parts.compactMap { part in
                    if part.type == .text, let text = part.text {
                        return text
                    }
                    return nil
                }.joined(separator: " ")
            }
        }

        // MARK: - Codable Implementation for MessageContent
        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let string):
                var container = encoder.singleValueContainer()
                try container.encode(string)
            case .multipart(let parts):
                var container = encoder.singleValueContainer()
                try container.encode(parts)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            // Try to decode as string first
            if let stringValue = try? container.decode(String.self) {
                self = .text(stringValue)
            } else if let arrayValue = try? container.decode([ContentPart].self) {
                self = .multipart(arrayValue)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "MessageContent must be either string or array of ContentPart"
                    )
                )
            }
        }
    }

    struct ContentPart: Codable, Sendable {
        let type: ContentType
        let text: String?
        let imageUrl: ImageUrl?

        enum ContentType: String, Codable, Sendable {
            case text = "text"
            case imageUrl = "image_url"
        }

        struct ImageUrl: Codable, Sendable {
            let url: String
            let detail: ImageDetail?

            enum ImageDetail: String, Codable, Sendable {
                case low = "low"
                case high = "high"
                case auto = "auto"
            }

            enum CodingKeys: String, CodingKey {
                case url, detail
            }
        }

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageUrl = "image_url"
        }
    }

    // MARK: - Convenience Initializers
    init(role: Role, content: MessageContent) {
        self.role = role
        self.content = content
    }

    init(role: Role, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(role: String, content: String) {
        self.role = Role(rawValue: role) ?? .user
        self.content = .text(content)
    }


    // MARK: - Validation
    enum ValidationError: Error, LocalizedError {
        case invalidContent(String)

        var errorDescription: String? {
            switch self {
            case .invalidContent(let reason):
                return "Invalid message content: \(reason)"
            }
        }
    }

    func validate() throws {
        let textContent = content.stringValue
        if textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Allow messages that only contain images (no text)
            if case .multipart(let parts) = content,
               parts.contains(where: { $0.type == .imageUrl }) {
                return // Valid: message with only images
            }
            throw ValidationError.invalidContent("Message content cannot be empty")
        }
    }

    // MARK: - Codable Implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role.rawValue, forKey: .role)

        // Encode content based on type
        switch content {
        case .text(let string):
            try container.encode(string, forKey: .content)
        case .multipart(let parts):
            try container.encode(parts, forKey: .content)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let roleString = try container.decode(String.self, forKey: .role)
        self.role = Role(rawValue: roleString) ?? .user

        // Try to decode as string first, then as array
        if let stringContent = try? container.decode(String.self, forKey: .content) {
            self.content = .text(stringContent)
        } else if let arrayContent = try? container.decode([ContentPart].self, forKey: .content) {
            self.content = .multipart(arrayContent)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Content must be either string or array of content parts"
                )
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}