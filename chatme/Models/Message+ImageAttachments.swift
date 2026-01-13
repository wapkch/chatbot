import Foundation
import CoreData
import os.log

/// Custom errors for image attachment operations
enum ImageAttachmentError: LocalizedError {
    case invalidAttachmentData
    case tooManyAttachments(current: Int, max: Int)
    case encodingFailed
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAttachmentData:
            return "Invalid image attachment data"
        case .tooManyAttachments(let current, let max):
            return "Too many attachments: \(current) exceeds maximum of \(max)"
        case .encodingFailed:
            return "Failed to encode image attachments"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        }
    }
}

extension Message {
    private static let logger = Logger(subsystem: "com.chatme.app", category: "ImageAttachments")

    /// Simple, reliable image attachments list with basic validation
    var imageAttachmentsList: [ImageAttachment] {
        get {
            guard let json = imageAttachments,
                  !json.isEmpty,
                  let data = json.data(using: .utf8),
                  let attachments = try? JSONDecoder().decode([ImageAttachment].self, from: data) else {
                return []
            }
            return attachments
        }
        set {
            // Simple validation - limit to max count
            let validatedAttachments = Array(newValue.prefix(ImageCompressionConfig.maxImageCount))

            // Simple encoding
            guard let data = try? JSONEncoder().encode(validatedAttachments),
                  let json = String(data: data, encoding: .utf8) else {
                Self.logger.error("Failed to encode image attachments")
                imageAttachments = nil
                return
            }

            imageAttachments = json
        }
    }

    /// Optimized property to check for images without full deserialization
    var hasImages: Bool {
        // Fast check without deserializing the entire array
        guard let json = imageAttachments, !json.isEmpty else {
            return false
        }

        // For non-empty JSON, we assume there are images
        // This avoids the expensive deserialization just to check emptiness
        return true
    }

}