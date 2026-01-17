import UIKit
import Foundation
import os.log

// Non-actor class to ensure UIKit operations can run on main thread
class ImageStorageService {
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.chatme.ImageStorageService", category: "ImageStorage")
    // Changed to serial queue to avoid race conditions with continuation resumption
    private let imageProcessingQueue = DispatchQueue(label: "com.chatme.image-processing", qos: .userInitiated)

    // Thread-safe directory creation state
    private var directoriesCreated = false
    private let directoryCreationQueue = DispatchQueue(label: "com.chatme.directory-creation", qos: .utility)

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
        // Directory creation will be handled lazily and safely
    }

    /// Centralized, thread-safe directory creation with proper error handling
    private func ensureDirectoriesExist() throws {
        try directoryCreationQueue.sync {
            // Double-check pattern to avoid redundant directory creation
            guard !directoriesCreated else { return }

            do {
                try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true, attributes: nil)
                directoriesCreated = true
                logger.info("Successfully created image storage directories")
            } catch {
                logger.error("Failed to create image directories: \(error.localizedDescription)")
                throw ImageStorageError.directoryCreationFailed
            }
        }
    }

    // MARK: - Public Methods

    func saveImage(_ image: UIImage) async throws -> ImageAttachment {
        // Ensure directories exist first
        try ensureDirectoriesExist()

        let attachment = ImageAttachment()

        // Perform CPU-intensive image processing on background queue
        return try await withCheckedThrowingContinuation { continuation in
            imageProcessingQueue.async {
                do {
                    // Compress image on background thread (CPU-intensive)
                    guard let compressedImage = self.compressImageOffMainThread(image, maxDimension: ImageCompressionConfig.maxDimension) else {
                        continuation.resume(throwing: ImageStorageError.compressionFailed)
                        return
                    }

                    // Convert to JPEG data on background thread
                    guard let originalData = compressedImage.jpegData(compressionQuality: ImageCompressionConfig.compressionQuality) else {
                        continuation.resume(throwing: ImageStorageError.compressionFailed)
                        return
                    }

                    // Generate thumbnail on background thread (CPU-intensive)
                    guard let thumbnail = self.generateThumbnailOffMainThread(from: compressedImage, size: ImageCompressionConfig.thumbnailSize) else {
                        continuation.resume(throwing: ImageStorageError.thumbnailGenerationFailed)
                        return
                    }

                    guard let thumbnailData = thumbnail.jpegData(compressionQuality: ImageCompressionConfig.thumbnailQuality) else {
                        continuation.resume(throwing: ImageStorageError.thumbnailGenerationFailed)
                        return
                    }

                    // File I/O operations on background thread
                    try originalData.write(to: attachment.originalURL)
                    try thumbnailData.write(to: attachment.thumbnailURL)

                    continuation.resume(returning: attachment)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadOriginalImage(for attachment: ImageAttachment) async throws -> UIImage {
        // Load data on background thread
        return try await withCheckedThrowingContinuation { continuation in
            imageProcessingQueue.async {
                do {
                    let data = try Data(contentsOf: attachment.originalURL)
                    // Create UIImage on background thread (thread-safe)
                    if let image = UIImage(data: data) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: ImageStorageError.loadFailed)
                    }
                } catch {
                    self.logger.error("Failed to load image data: \(error.localizedDescription)")
                    continuation.resume(throwing: ImageStorageError.loadFailed)
                }
            }
        }
    }

    func loadThumbnail(for attachment: ImageAttachment) async throws -> UIImage {
        // Load data on background thread
        return try await withCheckedThrowingContinuation { continuation in
            imageProcessingQueue.async {
                do {
                    let data = try Data(contentsOf: attachment.thumbnailURL)
                    // Create UIImage on background thread (thread-safe)
                    if let image = UIImage(data: data) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: ImageStorageError.loadFailed)
                    }
                } catch {
                    self.logger.error("Failed to load thumbnail data: \(error.localizedDescription)")
                    continuation.resume(throwing: ImageStorageError.loadFailed)
                }
            }
        }
    }

    func loadBase64(for attachment: ImageAttachment) async throws -> String {
        // Load and encode data on background thread
        return try await withCheckedThrowingContinuation { continuation in
            imageProcessingQueue.async {
                do {
                    let data = try Data(contentsOf: attachment.originalURL)
                    let base64String = data.base64EncodedString()
                    continuation.resume(returning: base64String)
                } catch {
                    self.logger.error("Failed to load image data for base64: \(error.localizedDescription)")
                    continuation.resume(throwing: ImageStorageError.loadFailed)
                }
            }
        }
    }

    func deleteImage(_ attachment: ImageAttachment) async throws {
        do {
            try fileManager.removeItem(at: attachment.originalURL)
        } catch {
            logger.error("Failed to delete original image: \(error.localizedDescription)")
            throw ImageStorageError.deleteFailed
        }

        do {
            try fileManager.removeItem(at: attachment.thumbnailURL)
        } catch {
            logger.error("Failed to delete thumbnail image: \(error.localizedDescription)")
            throw ImageStorageError.deleteFailed
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

    // MARK: - Private Methods (Image Processing)

    /// Background thread image compression using Core Graphics
    private func compressImageOffMainThread(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)

        if ratio >= 1.0 {
            return image
        }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        // Use Core Graphics instead of UIGraphics for background thread safety
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))

        guard let resizedCGImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: resizedCGImage, scale: 1.0, orientation: image.imageOrientation)
    }

    /// Background thread thumbnail generation using Core Graphics
    private func generateThumbnailOffMainThread(from image: UIImage, size: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let aspectRatio = image.size.width / image.size.height
        let thumbnailSize: CGSize

        if aspectRatio > 1 {
            thumbnailSize = CGSize(width: size, height: size / aspectRatio)
        } else {
            thumbnailSize = CGSize(width: size * aspectRatio, height: size)
        }

        // Use Core Graphics for background thread safety
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: Int(thumbnailSize.width),
            height: Int(thumbnailSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: thumbnailSize))

        guard let thumbnailCGImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: thumbnailCGImage, scale: 1.0, orientation: image.imageOrientation)
    }

    // MARK: - Legacy MainActor Methods (kept for compatibility if needed elsewhere)

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
    case deleteFailed
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
        case .deleteFailed:
            return "Failed to delete image"
        case .directoryCreationFailed:
            return "Failed to create necessary directories"
        }
    }
}