import UIKit
import Foundation
import os.log

// Non-actor class to ensure UIKit operations can run on main thread
class ImageStorageService {
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.chatme.ImageStorageService", category: "ImageStorage")

    private var imagesDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Images", isDirectory: true)
    }

    private var originalsDirectory: URL {
        imagesDirectory.appendingPathComponent("originals", isDirectory: true)
    }

    private var thumbnailsDirectory: URL {
        imagesDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        // Ensure directories exist synchronously during initialization
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create image directories: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

    func saveImage(_ image: UIImage) async throws -> ImageAttachment {
        // Ensure directories exist before attempting to save
        createDirectoriesIfNeeded()

        let attachment = ImageAttachment()

        // Perform UIKit operations on main thread
        let (compressedImage, originalData) = try await MainActor.run {
            guard let compressedImage = self.compressImage(image, maxDimension: ImageCompressionConfig.maxDimension),
                  let originalData = compressedImage.jpegData(compressionQuality: ImageCompressionConfig.compressionQuality) else {
                throw ImageStorageError.compressionFailed
            }
            return (compressedImage, originalData)
        }

        // File I/O can be done off main thread
        try originalData.write(to: attachment.originalURL)

        // Generate and save thumbnail on main thread
        let thumbnailData = try await MainActor.run {
            guard let thumbnail = self.generateThumbnail(from: compressedImage, size: ImageCompressionConfig.thumbnailSize),
                  let thumbnailData = thumbnail.jpegData(compressionQuality: ImageCompressionConfig.thumbnailQuality) else {
                throw ImageStorageError.thumbnailGenerationFailed
            }
            return thumbnailData
        }

        try thumbnailData.write(to: attachment.thumbnailURL)

        return attachment
    }

    func loadOriginalImage(for attachment: ImageAttachment) async throws -> UIImage {
        guard let data = try? Data(contentsOf: attachment.originalURL) else {
            throw ImageStorageError.loadFailed
        }

        // UIImage creation should be on main thread
        return try await MainActor.run {
            guard let image = UIImage(data: data) else {
                throw ImageStorageError.loadFailed
            }
            return image
        }
    }

    func loadThumbnail(for attachment: ImageAttachment) async throws -> UIImage {
        guard let data = try? Data(contentsOf: attachment.thumbnailURL) else {
            throw ImageStorageError.loadFailed
        }

        // UIImage creation should be on main thread
        return try await MainActor.run {
            guard let image = UIImage(data: data) else {
                throw ImageStorageError.loadFailed
            }
            return image
        }
    }

    func loadBase64(for attachment: ImageAttachment) async throws -> String {
        guard let data = try? Data(contentsOf: attachment.originalURL) else {
            throw ImageStorageError.loadFailed
        }
        return data.base64EncodedString()
    }

    func deleteImage(_ attachment: ImageAttachment) async throws {
        do {
            try fileManager.removeItem(at: attachment.originalURL)
        } catch {
            logger.error("Failed to delete original image: \(error.localizedDescription)")
            throw ImageStorageError.saveFailed
        }

        do {
            try fileManager.removeItem(at: attachment.thumbnailURL)
        } catch {
            logger.error("Failed to delete thumbnail image: \(error.localizedDescription)")
            throw ImageStorageError.saveFailed
        }
    }

    func deleteImages(_ attachments: [ImageAttachment]) async throws {
        // Make batch operations concurrent for better efficiency
        try await withThrowingTaskGroup(of: Void.self) { group in
            for attachment in attachments {
                group.addTask {
                    try await self.deleteImage(attachment)
                }
            }

            // Wait for all deletions to complete
            for try await _ in group {}
        }
    }

    // MARK: - Private Methods (UIKit operations - must run on main thread)

    @MainActor
    private func compressImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)

        if ratio >= 1.0 {
            return image
        }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage
    }

    @MainActor
    private func generateThumbnail(from image: UIImage, size: CGFloat) -> UIImage? {
        let aspectRatio = image.size.width / image.size.height
        let thumbnailSize: CGSize

        if aspectRatio > 1 {
            thumbnailSize = CGSize(width: size, height: size / aspectRatio)
        } else {
            thumbnailSize = CGSize(width: size * aspectRatio, height: size)
        }

        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return thumbnail
    }
}

// MARK: - Errors

enum ImageStorageError: Error, LocalizedError {
    case compressionFailed
    case thumbnailGenerationFailed
    case saveFailed
    case loadFailed
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress image"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .saveFailed:
            return "Failed to save image"
        case .loadFailed:
            return "Failed to load image"
        case .directoryCreationFailed:
            return "Failed to create necessary directories"
        }
    }
}