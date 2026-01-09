import Foundation

struct APIConfiguration: Codable, Identifiable {
    let id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var modelID: String
    var isDefault: Bool = false

    static let defaultConfigurations = [
        APIConfiguration(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "",
            modelID: "gpt-3.5-turbo",
            isDefault: true
        ),
        APIConfiguration(
            name: "Azure OpenAI",
            baseURL: "",
            apiKey: "",
            modelID: "gpt-35-turbo"
        )
    ]
}