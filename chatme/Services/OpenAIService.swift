import Foundation
import Combine

@MainActor
class OpenAIService: ObservableObject {
    // MARK: - Constants
    private enum Constants {
        static let streamDataPrefix = "data: "
        static let streamEndMarker = "data: [DONE]"
        static let contentTypeJSON = "application/json"
        static let authorizationHeaderPrefix = "Bearer "
    }

    // MARK: - Properties
    private let configurationManager: ConfigurationManager
    private var currentTask: Task<Void, Never>?

    // MARK: - Initializers
    init(configurationManager: ConfigurationManager? = nil) {
        self.configurationManager = configurationManager ?? ConfigurationManager()
    }

    // MARK: - Public Methods
    func sendMessage(
        _ message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage] = []
    ) -> AnyPublisher<String, APIError> {
        let subject = PassthroughSubject<String, APIError>()

        currentTask?.cancel()
        currentTask = Task {
            do {
                // Get API key from keychain
                guard let apiKey = await configurationManager.getAPIKey(for: configuration) else {
                    subject.send(completion: .failure(APIError.authenticationFailed("API key not found")))
                    return
                }

                // Build URL
                let urlString = configuration.baseURL.contains("/external/") || configuration.baseURL.contains("/chat/completions") ?
                    configuration.baseURL : "\(configuration.baseURL)/chat/completions"

                guard let url = URL(string: urlString) else {
                    subject.send(completion: .failure(APIError.invalidURL(configuration.baseURL)))
                    return
                }

                // Build request
                let request = try self.buildRequest(
                    url: url,
                    apiKey: apiKey,
                    message: message,
                    configuration: configuration,
                    conversationHistory: conversationHistory
                )

                // Use URLSession.bytes for true streaming
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    subject.send(completion: .failure(APIError.invalidResponse(statusCode: 0, message: "Invalid response")))
                    return
                }

                // Validate status code
                switch httpResponse.statusCode {
                case 200...299:
                    break
                case 401:
                    subject.send(completion: .failure(APIError.authenticationFailed("Invalid API key")))
                    return
                case 404:
                    subject.send(completion: .failure(APIError.modelNotFound(configuration.modelID)))
                    return
                case 429:
                    subject.send(completion: .failure(APIError.rateLimitExceeded(retryAfter: 60)))
                    return
                default:
                    subject.send(completion: .failure(APIError.invalidResponse(statusCode: httpResponse.statusCode, message: "Unknown error")))
                    return
                }

                // Read lines and parse SSE data
                for try await line in bytes.lines {
                    if Task.isCancelled { break }

                    if let content = self.parseSSELine(line) {
                        subject.send(content)
                    }
                }

                subject.send(completion: .finished)
            } catch let error as APIError {
                subject.send(completion: .failure(error))
            } catch {
                subject.send(completion: .failure(APIError.streamingError(error.localizedDescription)))
            }
        }

        return subject.eraseToAnyPublisher()
    }

    // MARK: - Private Methods

    private func parseSSELine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              trimmed != Constants.streamEndMarker,
              trimmed.hasPrefix(Constants.streamDataPrefix) else {
            return nil
        }

        let jsonString = String(trimmed.dropFirst(Constants.streamDataPrefix.count))

        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let response = try JSONDecoder().decode(ChatResponse.self, from: jsonData)
            return response.choices.first?.delta.content
        } catch {
            return nil
        }
    }

    private func buildRequest(
        url: URL,
        apiKey: String,
        message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage]
    ) throws -> URLRequest {
        var messages: [ChatMessage] = []

        // Add system prompts as the first messages if they exist and not already in history
        let validSystemPrompts = configuration.systemPrompts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !validSystemPrompts.isEmpty {
            let hasSystemMessages = conversationHistory.first?.role == .system
            if !hasSystemMessages {
                for systemPrompt in validSystemPrompts {
                    let systemMessage = ChatMessage(role: .system, content: systemPrompt)
                    messages.append(systemMessage)
                }
            }
        }

        // Add conversation history
        messages.append(contentsOf: conversationHistory)

        // Add the current user message
        messages.append(ChatMessage(role: .user, content: message))

        let requestBody: [String: Any] = [
            "model": configuration.modelID,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Constants.contentTypeJSON, forHTTPHeaderField: "Content-Type")
        request.setValue("\(Constants.authorizationHeaderPrefix)\(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw APIError.invalidJSONResponse
        }

        return request
    }

    func testConfiguration(_ configuration: APIConfiguration) -> AnyPublisher<TestResult, APIError> {
        let testMessage = "tell me a joke"

        return sendMessage(testMessage, configuration: configuration)
            .collect()
            .tryMap { responses -> TestResult in
                let fullResponse = responses.joined()

                let isSuccessful = !fullResponse.isEmpty
                let responseTime = Date()

                return TestResult(
                    isSuccessful: isSuccessful,
                    responseContent: fullResponse.isEmpty ? "No response received" : fullResponse,
                    responseTime: responseTime,
                    configuration: configuration
                )
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

    // MARK: - Test Result
    struct TestResult {
        let isSuccessful: Bool
        let responseContent: String
        let responseTime: Date
        let configuration: APIConfiguration

        var summary: String {
            if isSuccessful {
                return "✅ Configuration '\(configuration.name)' tested successfully"
            } else {
                return "❌ Configuration '\(configuration.name)' test failed"
            }
        }
    }

    // MARK: - Cancellation Management
    func cancelAllRequests() {
        currentTask?.cancel()
        currentTask = nil
    }

    deinit {
        currentTask?.cancel()
    }
}
