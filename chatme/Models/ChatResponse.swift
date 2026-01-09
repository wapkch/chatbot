import Foundation

struct ChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta
        let index: Int
        let finish_reason: String?

        struct Delta: Codable {
            let content: String?
            let role: String?
        }
    }
}