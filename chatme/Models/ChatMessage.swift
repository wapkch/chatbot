import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String

    enum Role: String, CaseIterable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
    }
}