//
//  TitleGenerationService.swift
//  chatme
//
//  Created by Claude on 2026/1/18.
//

import Foundation

/// Service for generating conversation titles using AI
class TitleGenerationService {
    static let shared = TitleGenerationService()

    private init() {}

    /// Generate a title based on the first user message and AI response
    /// - Parameters:
    ///   - userMessage: The first user message
    ///   - aiResponse: The AI's response (optional)
    ///   - configuration: API configuration to use
    ///   - configurationManager: Configuration manager for API key
    /// - Returns: Generated title (max 50 characters)
    func generateTitle(
        userMessage: String,
        aiResponse: String? = nil,
        configuration: APIConfiguration,
        configurationManager: ConfigurationManager
    ) async throws -> String {
        // Get API key
        guard let apiKey = await configurationManager.getAPIKey(for: configuration) else {
            throw TitleGenerationError.apiKeyNotFound
        }

        // Build URL
        let urlString = configuration.baseURL.contains("/external/") || configuration.baseURL.contains("/chat/completions") ?
            configuration.baseURL : "\(configuration.baseURL)/chat/completions"

        guard let url = URL(string: urlString) else {
            throw TitleGenerationError.invalidURL
        }

        // Prepare prompt for title generation
        let prompt = buildTitlePrompt(userMessage: userMessage, aiResponse: aiResponse)

        // Build request
        let messages: [[String: String]] = [
            ["role": "user", "content": prompt]
        ]

        let requestBody: [String: Any] = [
            "model": configuration.modelID,
            "messages": messages,
            "max_tokens": 50,
            "temperature": 0.7,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TitleGenerationError.requestFailed
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TitleGenerationError.invalidResponse
        }

        // Clean up the title (remove quotes, trim, limit length)
        let title = cleanupTitle(content)
        return title
    }

    /// Build a prompt for title generation
    private func buildTitlePrompt(userMessage: String, aiResponse: String?) -> String {
        let conversationContext: String
        if let response = aiResponse {
            conversationContext = """
            User: \(userMessage)
            Assistant: \(response)
            """
        } else {
            conversationContext = "User: \(userMessage)"
        }

        return """
        Based on the following conversation, generate a short, concise title (maximum 6 words, in the same language as the user's message):

        \(conversationContext)

        Title:
        """
    }

    /// Clean up and format the generated title
    private func cleanupTitle(_ rawTitle: String) -> String {
        var title = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        // Remove common prefixes
        let prefixes = ["Title:", "title:", "标题:", "标题："]
        for prefix in prefixes {
            if title.hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Limit length to 50 characters
        if title.count > 50 {
            let endIndex = title.index(title.startIndex, offsetBy: 50)
            title = String(title[..<endIndex]) + "..."
        }

        // Fallback if empty
        if title.isEmpty {
            title = "新会话"
        }

        return title
    }
}

// MARK: - Errors
enum TitleGenerationError: Error, LocalizedError {
    case apiKeyNotFound
    case invalidURL
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return "API key not found"
        case .invalidURL:
            return "Invalid API URL"
        case .requestFailed:
            return "Title generation request failed"
        case .invalidResponse:
            return "Invalid response from API"
        }
    }
}
