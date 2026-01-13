import Foundation
import CoreData

extension Message {
    var imageAttachmentsList: [ImageAttachment] {
        get {
            guard let json = imageAttachments,
                  let data = json.data(using: .utf8),
                  let attachments = try? JSONDecoder().decode([ImageAttachment].self, from: data) else {
                return []
            }
            return attachments
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                imageAttachments = nil
                return
            }
            imageAttachments = json
        }
    }

    var hasImages: Bool {
        !imageAttachmentsList.isEmpty
    }
}