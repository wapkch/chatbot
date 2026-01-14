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

    /// Send a text-only message (legacy method)
    func sendMessage(
        _ message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage] = []
    ) -> AnyPublisher<String, APIError> {
        let userMessage = ChatMessage(role: .user, content: message)
        return sendMessage(userMessage, configuration: configuration, conversationHistory: conversationHistory)
    }

    /// Send a message with support for images (Vision API)
    func sendMessage(
        _ message: ChatMessage,
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
                let request = try await self.buildRequest(
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
        message: ChatMessage,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage]
    ) async throws -> URLRequest {
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

        // Process the current message (resolve image attachments if any)
        let processedMessage = try await processMessageContent(message)
        messages.append(processedMessage)

        // Convert messages to API format
        let messagesForAPI = try messages.map { message in
            try messageToAPIFormat(message)
        }

        let requestBody: [String: Any] = [
            "model": configuration.modelID,
            "messages": messagesForAPI,
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

    /// Process message content, resolving image attachment placeholders to base64 data URLs
    private func processMessageContent(_ message: ChatMessage) async throws -> ChatMessage {
        guard case .multipart(let parts) = message.content else {
            return message // Text-only message, no processing needed
        }

        var processedParts: [ChatMessage.ContentPart] = []

        for part in parts {
            switch part.type {
            case .text:
                processedParts.append(part) // Text parts remain unchanged

            case .imageUrl:
                guard let imageUrl = part.imageUrl else {
                    throw APIError.invalidJSONResponse
                }

                // Check if this is a placeholder URL that needs resolution
                if imageUrl.url.hasPrefix("attachment:") {
                    let idString = String(imageUrl.url.dropFirst("attachment:".count))
                    guard let attachmentId = UUID(uuidString: idString) else {
                        throw APIError.invalidJSONResponse
                    }

                    // Create ImageAttachment and load base64 data
                    let attachment = ImageAttachment(id: attachmentId, fileName: nil)
                    let base64Data = try await ImageStorageService.shared.loadBase64(for: attachment)

                    // Determine MIME type based on file extension
                    let mimeType = attachment.fileName.hasSuffix(".png") ? "image/png" : "image/jpeg"
                    let dataURL = "data:\(mimeType);base64,\(base64Data)"

                    // Create processed part with actual base64 data URL
                    let processedImageUrl = ChatMessage.ContentPart.ImageUrl(
                        url: dataURL,
                        detail: imageUrl.detail
                    )
                    processedParts.append(ChatMessage.ContentPart(
                        type: .imageUrl,
                        text: nil,
                        imageUrl: processedImageUrl
                    ))
                } else {
                    processedParts.append(part) // Already a valid URL, keep as-is
                }
            }
        }

        return ChatMessage(role: message.role, content: .multipart(processedParts))
    }

    /// Convert ChatMessage to API-compatible dictionary format
    private func messageToAPIFormat(_ message: ChatMessage) throws -> [String: Any] {
        switch message.content {
        case .text(let text):
            // Simple text message
            return [
                "role": message.role.rawValue,
                "content": text
            ]

        case .multipart(let parts):
            // Vision API format with content array
            let contentParts = parts.map { part -> [String: Any] in
                switch part.type {
                case .text:
                    return [
                        "type": "text",
                        "text": part.text ?? ""
                    ]
                case .imageUrl:
                    var imageUrlDict: [String: Any] = [
                        "url": part.imageUrl?.url ?? ""
                    ]
                    if let detail = part.imageUrl?.detail {
                        imageUrlDict["detail"] = detail.rawValue
                    }
                    return [
                        "type": "image_url",
                        "image_url": imageUrlDict
                    ]
                }
            }

            return [
                "role": message.role.rawValue,
                "content": contentParts
            ]
        }
    }

    func testConfiguration(_ configuration: APIConfiguration) -> AnyPublisher<TestResult, APIError> {
        let testMessage = ChatMessage(role: .user, content: "tell me a joke")

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
