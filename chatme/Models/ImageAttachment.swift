import Foundation

struct ImageAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date

    init(id: UUID = UUID(), fileName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.fileName = Self.validateAndGenerateFileName(fileName, id: id)
        self.createdAt = createdAt
    }

    // MARK: - Private Helpers

    private static func validateAndGenerateFileName(_ fileName: String?, id: UUID) -> String {
        guard let fileName = fileName, !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Default to JPEG for backward compatibility
            return "\(id.uuidString).jpg"
        }

        // Validate filename
        let validatedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure it has a valid image extension
        let pathExtension = (validatedName as NSString).pathExtension.lowercased()
        let supportedExtensions = ["jpg", "jpeg", "png", "heic"]

        if supportedExtensions.contains(pathExtension) {
            return validatedName
        } else {
            // If no valid extension, add .jpg for backward compatibility
            return "\(validatedName).jpg"
        }
    }

    private static func getFileExtension(from fileName: String) -> String {
        return (fileName as NSString).pathExtension.lowercased()
    }

    private static func getFileNameWithoutExtension(from fileName: String) -> String {
        return (fileName as NSString).deletingPathExtension
    }

    // MARK: - Computed Properties

    private static var imagesDirectory: URL {
        // Safe array access with fallback
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // Fallback to temporary directory if documents directory is unavailable
            return FileManager.default.temporaryDirectory.appendingPathComponent("Images", isDirectory: true)
        }
        let imagesDir = documentsPath.appendingPathComponent("Images", isDirectory: true)

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Warning: Failed to create images directory: \(error)")
        }

        return imagesDir
    }

    var originalURL: URL {
        let imagesDir = Self.imagesDirectory
        let originalsDir = imagesDir.appendingPathComponent("originals", isDirectory: true)

        // Ensure originals directory exists
        do {
            try FileManager.default.createDirectory(at: originalsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Warning: Failed to create originals directory: \(error)")
        }

        return originalsDir.appendingPathComponent(fileName)
    }

    var thumbnailURL: URL {
        let imagesDir = Self.imagesDirectory
        let thumbnailsDir = imagesDir.appendingPathComponent("thumbnails", isDirectory: true)

        // Ensure thumbnails directory exists
        do {
            try FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Warning: Failed to create thumbnails directory: \(error)")
        }

        let fileNameWithoutExt = Self.getFileNameWithoutExtension(from: fileName)
        let fileExt = Self.getFileExtension(from: fileName)
        let thumbName = "\(fileNameWithoutExt)_thumb.\(fileExt.isEmpty ? "jpg" : fileExt)"

        return thumbnailsDir.appendingPathComponent(thumbName)
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
    static let thumbnailQuality: CGFloat = 0.7
    static let thumbnailSize: CGFloat = 200
    static let maxImageCount: Int = 4
}
