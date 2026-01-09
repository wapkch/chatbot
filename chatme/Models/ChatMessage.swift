import Foundation

struct ChatMessage: Codable {
    let role: Role
    let content: String

    enum Role: String, CaseIterable, Codable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
    }

    // MARK: - Initializers
    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    init(role: String, content: String) {
        self.role = Role(rawValue: role) ?? .user
        self.content = content
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
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.invalidContent("Message content cannot be empty")
        }
    }

    // MARK: - Codable Implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role.rawValue, forKey: .role)
        try container.encode(content, forKey: .content)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let roleString = try container.decode(String.self, forKey: .role)
        self.role = Role(rawValue: roleString) ?? .user
        self.content = try container.decode(String.self, forKey: .content)
    }

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}