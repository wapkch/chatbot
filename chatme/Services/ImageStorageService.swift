import UIKit
import Foundation

actor ImageStorageService {
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default
    private let processingQueue = DispatchQueue(label: "com.chatme.imageProcessing", qos: .userInitiated)

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
        Task {
            await createDirectoriesIfNeeded()
        }
    }

    private func createDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create image directories: \(error)")
        }
    }

    // MARK: - Public Methods

    func saveImage(_ image: UIImage) async throws -> ImageAttachment {
        let attachment = ImageAttachment()

        // Compress and save original
        guard let compressedImage = compressImage(image, maxDimension: ImageCompressionConfig.maxDimension),
              let originalData = compressedImage.jpegData(compressionQuality: ImageCompressionConfig.compressionQuality) else {
            throw ImageStorageError.compressionFailed
        }

        try originalData.write(to: attachment.originalURL)

        // Generate and save thumbnail
        guard let thumbnail = generateThumbnail(from: compressedImage, size: ImageCompressionConfig.thumbnailSize),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else {
            throw ImageStorageError.thumbnailGenerationFailed
        }

        try thumbnailData.write(to: attachment.thumbnailURL)

        return attachment
    }

    func loadOriginalImage(for attachment: ImageAttachment) async -> UIImage? {
        guard let data = try? Data(contentsOf: attachment.originalURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    func loadThumbnail(for attachment: ImageAttachment) async -> UIImage? {
        guard let data = try? Data(contentsOf: attachment.thumbnailURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    func loadBase64(for attachment: ImageAttachment) async -> String? {
        guard let data = try? Data(contentsOf: attachment.originalURL) else {
            return nil
        }
        return data.base64EncodedString()
    }

    func deleteImage(_ attachment: ImageAttachment) async {
        try? fileManager.removeItem(at: attachment.originalURL)
        try? fileManager.removeItem(at: attachment.thumbnailURL)
    }

    func deleteImages(_ attachments: [ImageAttachment]) async {
        for attachment in attachments {
            await deleteImage(attachment)
        }
    }

    // MARK: - Private Methods

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
        }
    }
}