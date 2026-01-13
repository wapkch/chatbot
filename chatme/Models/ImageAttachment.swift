import Foundation

struct ImageAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date

    init(id: UUID = UUID(), fileName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.fileName = fileName ?? "\(id.uuidString).jpg"
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    private static var imagesDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Images", isDirectory: true)
    }

    var originalURL: URL {
        Self.imagesDirectory
            .appendingPathComponent("originals", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    var thumbnailURL: URL {
        let thumbName = fileName.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
        return Self.imagesDirectory
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(thumbName)
    }

    // MARK: - Equatable

    static func == (lhs: ImageAttachment, rhs: ImageAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Compression Configuration

struct ImageCompressionConfig {
    static let maxDimension: CGFloat = 2048
    static let compressionQuality: CGFloat = 0.8
    static let thumbnailSize: CGFloat = 200
    static let maxImageCount: Int = 4
}
