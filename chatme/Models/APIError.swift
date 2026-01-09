import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidURL(String)
    case authenticationFailed(String)
    case modelNotFound(String)
    case rateLimitExceeded(retryAfter: TimeInterval)
    case networkTimeout
    case invalidResponse(statusCode: Int, message: String)
    case invalidJSONResponse
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url). Please check your base URL configuration."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message). Please check your API key."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please check your model ID configuration."
        case .rateLimitExceeded(let retryAfter):
            return "Rate limit exceeded. Please try again in \(Int(retryAfter)) seconds."
        case .networkTimeout:
            return "Network timeout. Please check your internet connection."
        case .invalidResponse(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .invalidJSONResponse:
            return "Invalid response format from server."
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Verify your base URL in Settings → API Configuration"
        case .authenticationFailed:
            return "Test your API key in Settings → API Configuration"
        case .modelNotFound:
            return "Check available models in your API documentation"
        case .rateLimitExceeded:
            return "Wait a moment before sending another message"
        case .networkTimeout:
            return "Check your internet connection and try again"
        case .invalidResponse:
            return "Contact your API provider if this persists"
        case .invalidJSONResponse:
            return "This may be a temporary server issue"
        case .streamingError:
            return "Try sending your message again"
        }
    }
}