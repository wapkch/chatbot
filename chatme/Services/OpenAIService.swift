import Foundation
import Combine

// MARK: - Protocol for dependency injection
protocol URLSessionProtocol {
    func dataTaskPublisher(for request: URLRequest) -> URLSession.DataTaskPublisher
}

extension URLSession: URLSessionProtocol {}

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
    private var cancellables = Set<AnyCancellable>()
    private let configurationManager: ConfigurationManager
    private let urlSession: URLSessionProtocol
    // Buffer for accumulating incomplete SSE lines
    private var streamBuffer = ""

    // MARK: - Initializers
    init(configurationManager: ConfigurationManager? = nil, urlSession: URLSessionProtocol = URLSession.shared) {
        self.configurationManager = configurationManager ?? ConfigurationManager()
        self.urlSession = urlSession
    }

    // MARK: - Public Methods
    func sendMessage(
        _ message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage] = []
    ) -> AnyPublisher<String, APIError> {

        // Reset buffer for new stream
        streamBuffer = ""

        return Deferred {
            Future<AnyPublisher<String, APIError>, APIError> { [weak self] promise in
                Task {
                    guard let self = self else {
                        promise(.failure(APIError.streamingError("Service deallocated")))
                        return
                    }

                    do {
                        let publisher = try await self.createStreamingPublisher(
                            message: message,
                            configuration: configuration,
                            conversationHistory: conversationHistory
                        )
                        promise(.success(publisher))
                    } catch let error as APIError {
                        promise(.failure(error))
                    } catch {
                        promise(.failure(APIError.streamingError(error.localizedDescription)))
                    }
                }
            }
            .flatMap { publisher in
                publisher
            }
            .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Private Methods
    private func createStreamingPublisher(
        message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage]
    ) async throws -> AnyPublisher<String, APIError> {

        // Get API key from keychain
        guard let apiKey = await configurationManager.getAPIKey(for: configuration) else {
            throw APIError.authenticationFailed("API key not found")
        }

        // Use baseURL directly if it's a complete endpoint, otherwise append /chat/completions
        let urlString = configuration.baseURL.contains("/external/") || configuration.baseURL.contains("/chat/completions") ?
            configuration.baseURL : "\(configuration.baseURL)/chat/completions"

        print("🔍 DEBUG: Constructed URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL(configuration.baseURL)
        }

        // Build request
        let request = try buildRequest(
            url: url,
            apiKey: apiKey,
            message: message,
            configuration: configuration,
            conversationHistory: conversationHistory
        )

        return urlSession.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response -> Data in
                guard let self = self else {
                    throw APIError.streamingError("Service deallocated")
                }
                return try self.validateHTTPResponse(data: data, response: response, modelID: configuration.modelID)
            }
            .compactMap { [weak self] data -> [String]? in
                guard let self = self else { return nil }
                let chunks = self.parseStreamingData(data)
                return chunks.isEmpty ? nil : chunks
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

    private func buildRequest(
        url: URL,
        apiKey: String,
        message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage]
    ) throws -> URLRequest {
        var messages = conversationHistory
        messages.append(ChatMessage(role: .user, content: message))

        let requestBody: [String: Any] = [
            "model": configuration.modelID,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true
        ]

        print("🔍 DEBUG: Request body: \(requestBody)")
        print("🔍 DEBUG: API Key (first 10 chars): \(String(apiKey.prefix(10)))...")

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

    private func validateHTTPResponse(data: Data, response: URLResponse, modelID: String) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: 0, message: "Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.authenticationFailed("Invalid API key")
        case 404:
            throw APIError.modelNotFound(modelID)
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"
            throw APIError.rateLimitExceeded(retryAfter: TimeInterval(retryAfter) ?? 60)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func parseStreamingData(_ data: Data) -> [String] {
        let newString = String(data: data, encoding: .utf8) ?? ""

        // Append new data to buffer
        streamBuffer += newString

        // Split by lines, keeping incomplete last line in buffer
        let lines = streamBuffer.components(separatedBy: "\n")
        var completeLines = Array(lines.dropLast()) // All lines except the potentially incomplete last one

        // Keep the last line in buffer (it might be incomplete)
        streamBuffer = lines.last ?? ""

        // Check for stream end marker
        let hasEndMarker = completeLines.contains(Constants.streamEndMarker)
        if hasEndMarker {
            // If we have [DONE] and buffer content, process the buffer as final line
            if !streamBuffer.isEmpty && streamBuffer.hasPrefix(Constants.streamDataPrefix) && streamBuffer != Constants.streamEndMarker {
                completeLines.append(streamBuffer)
                streamBuffer = "" // Clear buffer after processing
            }
        }

        let filteredLines = completeLines.filter { $0.hasPrefix(Constants.streamDataPrefix) && $0 != Constants.streamEndMarker }

        return filteredLines.compactMap { [weak self] line in
            guard let self = self else { return nil }
            return self.extractContentFromStreamLine(line)
        }
    }

    private func extractContentFromStreamLine(_ line: String) -> String? {
        let jsonString = String(line.dropFirst(Constants.streamDataPrefix.count))

        guard let jsonData = jsonString.data(using: .utf8) else {
            print("Warning: Failed to convert stream line to data: \(line)")
            return nil
        }

        do {
            let response = try JSONDecoder().decode(ChatResponse.self, from: jsonData)
            return response.choices.first?.delta.content
        } catch {
            print("Warning: Failed to decode stream response: \(error.localizedDescription)")
            return nil
        }
    }

    func testConfiguration(_ configuration: APIConfiguration) -> AnyPublisher<TestResult, APIError> {
        let testMessage = "tell me a joke" // Use the exact same message as working curl

        print("🔍 DEBUG: Testing configuration '\(configuration.name)'")
        print("🔍 DEBUG: Base URL: \(configuration.baseURL)")
        print("🔍 DEBUG: Model ID: \(configuration.modelID)")

        return sendMessage(testMessage, configuration: configuration)
            .collect()
            .tryMap { responses -> TestResult in
                let fullResponse = responses.joined()
                print("🔍 DEBUG: Received response: \(fullResponse.prefix(100))...")

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
                print("🔍 DEBUG: Error occurred: \(error)")
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
        cancellables.removeAll()
    }

    deinit {
        cancellables.removeAll()
    }
}