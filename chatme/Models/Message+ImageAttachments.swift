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

    // Cache to avoid repeated deserialization - thread-safe using private queue
    private static var attachmentCache: [String: [ImageAttachment]] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.chatme.attachment-cache", attributes: .concurrent)

    /// Cached image attachments list with transaction safety and validation
    var imageAttachmentsList: [ImageAttachment] {
        get {
            // Fast path for empty attachments
            guard let json = imageAttachments, !json.isEmpty else {
                return []
            }

            // Check cache first (thread-safe read)
            return Self.cacheQueue.sync {
                if let cached = Self.attachmentCache[json] {
                    return cached
                }

                // Parse and cache the result
                guard let data = json.data(using: .utf8),
                      let attachments = try? JSONDecoder().decode([ImageAttachment].self, from: data) else {
                    Self.logger.warning("Failed to decode image attachments for message: \(self.id?.uuidString ?? "unknown")")
                    return []
                }

                // Cache the result (limit cache size to prevent memory issues)
                if Self.attachmentCache.count > 100 {
                    Self.attachmentCache.removeAll(keepingCapacity: false)
                }
                Self.attachmentCache[json] = attachments

                return attachments
            }
        }
        set {
            // Validate attachment count
            do {
                try validateAttachments(newValue)
            } catch {
                Self.logger.error("Validation failed for image attachments: \(error.localizedDescription)")
                // For transaction safety, we don't modify the property on validation failure
                return
            }

            // Perform Core Data modification within transaction safety
            performSafeUpdate { [weak self] in
                guard let self = self else { return }

                do {
                    // Clear old value from cache first
                    if let oldJson = self.imageAttachments {
                        Self.cacheQueue.async(flags: .barrier) {
                            Self.attachmentCache.removeValue(forKey: oldJson)
                        }
                    }

                    // Handle empty array case
                    if newValue.isEmpty {
                        self.imageAttachments = nil
                        return
                    }

                    // Encode new value
                    let data = try JSONEncoder().encode(newValue)
                    guard let json = String(data: data, encoding: .utf8) else {
                        throw ImageAttachmentError.encodingFailed
                    }

                    // Update the Core Data property
                    self.imageAttachments = json

                    // Update cache with new value
                    Self.cacheQueue.async(flags: .barrier) {
                        Self.attachmentCache[json] = newValue
                    }

                } catch {
                    Self.logger.error("Failed to set image attachments: \(error.localizedDescription)")
                    // Note: We don't set the property on encoding failure for transaction safety
                }
            }
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

    // MARK: - Private Helper Methods

    /// Validate attachments against business rules
    private func validateAttachments(_ attachments: [ImageAttachment]) throws {
        // Check count limit
        if attachments.count > ImageCompressionConfig.maxImageCount {
            throw ImageAttachmentError.tooManyAttachments(
                current: attachments.count,
                max: ImageCompressionConfig.maxImageCount
            )
        }

        // Validate each attachment
        for attachment in attachments {
            // Check if file name is valid
            if attachment.fileName.isEmpty {
                throw ImageAttachmentError.validationFailed("Empty file name")
            }

            // Additional validation can be added here (file size, format, etc.)
        }
    }

    /// Perform Core Data update with transaction safety
    private func performSafeUpdate(_ updateBlock: @escaping () -> Void) {
        guard let context = managedObjectContext else {
            Self.logger.error("No managed object context available for image attachment update")
            return
        }

        // Perform update on the context's queue for thread safety
        context.perform {
            updateBlock()

            // Save context if there are changes
            if context.hasChanges {
                do {
                    try context.save()
                    Self.logger.debug("Successfully saved image attachment changes")
                } catch {
                    Self.logger.error("Failed to save image attachment changes: \(error.localizedDescription)")
                    context.rollback()
                }
            }
        }
    }

    // MARK: - Cache Management

    /// Clear the attachment cache (useful for memory management)
    static func clearAttachmentCache() {
        cacheQueue.async(flags: .barrier) {
            attachmentCache.removeAll()
            logger.debug("Cleared image attachment cache")
        }
    }
}