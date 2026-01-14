import Foundation

// MARK: - ChatMessage + ImageAttachment Integration
extension ChatMessage {
    /// Creates a ChatMessage with text and image attachments for Vision API
    init(role: Role, text: String, imageAttachments: [ImageAttachment]) {
        self.role = role

        if imageAttachments.isEmpty {
            self.content = .text(text)
        } else {
            var parts: [ContentPart] = []

            // Add text if not empty
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(ContentPart(
                    type: .text,
                    text: text,
                    imageUrl: nil
                ))
            }

            // Add images as placeholder URLs that will be resolved by OpenAIService
            for attachment in imageAttachments {
                // Note: The actual base64 conversion will be done in OpenAIService
                // Here we just store a placeholder that will be replaced during API call
                parts.append(ContentPart(
                    type: .imageUrl,
                    text: nil,
                    imageUrl: ContentPart.ImageUrl(
                        url: "attachment:\(attachment.id.uuidString)",
                        detail: .auto
                    )
                ))
            }

            self.content = .multipart(parts)
        }
    }

    /// Extracts image attachment IDs from the message content
    var imageAttachmentIds: [UUID] {
        guard case .multipart(let parts) = content else { return [] }

        return parts.compactMap { part in
            guard part.type == .imageUrl,
                  let imageUrl = part.imageUrl,
                  imageUrl.url.hasPrefix("attachment:") else {
                return nil
            }

            let idString = String(imageUrl.url.dropFirst("attachment:".count))
            return UUID(uuidString: idString)
        }
    }

    /// Checks if this message contains image attachments
    var hasImages: Bool {
        !imageAttachmentIds.isEmpty
    }
}