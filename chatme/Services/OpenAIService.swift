import Foundation
import Combine

@MainActor
class OpenAIService: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private let configurationManager: ConfigurationManager

    init(configurationManager: ConfigurationManager? = nil) {
        self.configurationManager = configurationManager ?? ConfigurationManager()
    }

    func sendMessage(
        _ message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage] = []
    ) async -> AnyPublisher<String, APIError> {

        // Get API key from keychain
        guard let apiKey = await configurationManager.getAPIKey(for: configuration) else {
            return Fail(error: APIError.authenticationFailed("API key not found"))
                .eraseToAnyPublisher()
        }

        guard let url = URL(string: "\(configuration.baseURL)/chat/completions") else {
            return Fail(error: APIError.invalidURL(configuration.baseURL))
                .eraseToAnyPublisher()
        }

        var messages = conversationHistory
        messages.append(ChatMessage(role: "user", content: message))

        let requestBody: [String: Any] = [
            "model": configuration.modelID,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return Fail(error: APIError.invalidJSONResponse)
                .eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse(statusCode: 0, message: "Invalid response")
                }

                if httpResponse.statusCode == 401 {
                    throw APIError.authenticationFailed("Invalid API key")
                } else if httpResponse.statusCode == 404 {
                    throw APIError.modelNotFound(configuration.modelID)
                } else if httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"
                    throw APIError.rateLimitExceeded(retryAfter: TimeInterval(retryAfter) ?? 60)
                } else if httpResponse.statusCode >= 400 {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw APIError.invalidResponse(statusCode: httpResponse.statusCode, message: message)
                }

                return data
            }
            .compactMap { data -> [String] in
                let string = String(data: data, encoding: .utf8) ?? ""
                return string.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("data: ") && $0 != "data: [DONE]" }
                    .compactMap { line in
                        let jsonString = String(line.dropFirst(6))
                        guard let jsonData = jsonString.data(using: .utf8),
                              let response = try? JSONDecoder().decode(ChatResponse.self, from: jsonData),
                              let content = response.choices.first?.delta.content else {
                            return nil
                        }
                        return content
                    }
            }
            .flatMap { chunks -> Publishers.Sequence<[String], Never> in
                Publishers.Sequence(sequence: chunks)
            }
            .mapError { error in
                if let apiError = error as? APIError {
                    return apiError
                } else {
                    return APIError.streamingError(error.localizedDescription)
                }
            }
            .eraseToAnyPublisher()
    }

    func testConfiguration(_ configuration: APIConfiguration) async -> AnyPublisher<Bool, APIError> {
        let publisher = await sendMessage("Hello", configuration: configuration)
        return publisher
            .map { _ in true }
            .reduce(false) { _, _ in true }
            .eraseToAnyPublisher()
    }
}