# Image Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add image sending functionality to ChatMe, allowing users to select photos from album or take photos, then send them via OpenAI Vision API.

**Architecture:** Bottom-up implementation starting with data models and storage service, then UI components, finally integrating with existing ChatViewModel and OpenAIService. Uses PHPicker for photo selection, file system for image storage, and Base64 encoding for API transmission.

**Tech Stack:** SwiftUI, PhotosUI (PHPickerViewController), AVFoundation (Camera), Core Data, UIKit (UIImagePickerController for camera)

---

## Task 1: Create ImageAttachment Model

**Files:**
- Create: `chatme/Models/ImageAttachment.swift`

**Step 1: Create the ImageAttachment model file**

```swift
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
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Models/ImageAttachment.swift
git commit -m "feat: add ImageAttachment model for image storage"
```

---

## Task 2: Create ImageStorageService

**Files:**
- Create: `chatme/Services/ImageStorageService.swift`

**Step 1: Create the ImageStorageService file**

```swift
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
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Services/ImageStorageService.swift
git commit -m "feat: add ImageStorageService for image compression and storage"
```

---

## Task 3: Update Core Data Model

**Files:**
- Modify: `chatme/Models/DataModel.xcdatamodeld/DataModel.xcdatamodel/contents`
- Modify: `chatme/Models/Message.swift` (if exists, or Core Data will auto-generate)

**Step 1: Add imageAttachments attribute to Message entity**

Update the Core Data model XML to add `imageAttachments` attribute:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="22758" systemVersion="23F79" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Conversation" representedClassName="Conversation" syncable="YES">
        <attribute name="createdAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="messageCount" optional="YES" attributeType="Integer 32" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="title" optional="YES" attributeType="String"/>
        <attribute name="updatedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="messages" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Message" inverseName="conversation" inverseEntity="Message"/>
    </entity>
    <entity name="Message" representedClassName="Message" syncable="YES">
        <attribute name="content" optional="YES" attributeType="String"/>
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="imageAttachments" optional="YES" attributeType="String"/>
        <attribute name="isFromUser" optional="YES" attributeType="Boolean" usesScalarValueType="YES"/>
        <attribute name="timestamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="conversation" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Conversation" inverseName="messages" inverseEntity="Conversation"/>
    </entity>
</model>
```

**Step 2: Add Message extension for image attachments**

Create: `chatme/Models/Message+ImageAttachments.swift`

```swift
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
```

**Step 3: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add chatme/Models/DataModel.xcdatamodeld/DataModel.xcdatamodel/contents
git add chatme/Models/Message+ImageAttachments.swift
git commit -m "feat: add imageAttachments field to Message entity"
```

---

## Task 4: Create ImageThumbnailView Component

**Files:**
- Create: `chatme/Views/ImageThumbnailView.swift`

**Step 1: Create the ImageThumbnailView file**

```swift
import SwiftUI

struct ImageThumbnailView: View {
    let attachment: ImageAttachment
    let size: CGFloat
    var isSelected: Bool = false
    var selectionIndex: Int? = nil
    var showDeleteButton: Bool = false
    var onDelete: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            .onTapGesture {
                onTap?()
            }

            // Selection index badge
            if let index = selectionIndex {
                Text("\(index)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .offset(x: -4, y: 4)
            }

            // Delete button
            if showDeleteButton {
                Button(action: {
                    onDelete?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .offset(x: -4, y: 4)
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        thumbnailImage = await ImageStorageService.shared.loadThumbnail(for: attachment)
        isLoading = false
    }
}

// MARK: - Preview Image Thumbnail (for input area)

struct PreviewImageThumbnail: View {
    let attachment: ImageAttachment
    let onDelete: () -> Void

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .offset(x: 6, y: -6)
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        thumbnailImage = await ImageStorageService.shared.loadThumbnail(for: attachment)
        isLoading = false
    }
}
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Views/ImageThumbnailView.swift
git commit -m "feat: add ImageThumbnailView component"
```

---

## Task 5: Create ImagePreviewRow Component

**Files:**
- Create: `chatme/Views/ImagePreviewRow.swift`

**Step 1: Create the ImagePreviewRow file**

```swift
import SwiftUI

struct ImagePreviewRow: View {
    let attachments: [ImageAttachment]
    let onDelete: (ImageAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    PreviewImageThumbnail(
                        attachment: attachment,
                        onDelete: {
                            onDelete(attachment)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.chatBackground)
    }
}
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Views/ImagePreviewRow.swift
git commit -m "feat: add ImagePreviewRow for input area image preview"
```

---

## Task 6: Create ImagePickerSheet Component

**Files:**
- Create: `chatme/Views/ImagePickerSheet.swift`

**Step 1: Create the ImagePickerSheet file**

```swift
import SwiftUI
import PhotosUI
import AVFoundation

struct ImagePickerSheet: View {
    @Binding var selectedAttachments: [ImageAttachment]
    @Binding var isPresented: Bool
    let maxSelection: Int

    @State private var recentPhotos: [PHAsset] = []
    @State private var selectedAssets: [PHAsset] = []
    @State private var showingCamera = false
    @State private var showingFullPicker = false
    @State private var isProcessing = false
    @State private var cameraAvailable = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ChatMe")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("All Photos") {
                    showingFullPicker = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Photo grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Camera button
                    if cameraAvailable {
                        Button(action: {
                            showingCamera = true
                        }) {
                            VStack {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Recent photos
                    ForEach(recentPhotos, id: \.localIdentifier) { asset in
                        RecentPhotoThumbnail(
                            asset: asset,
                            isSelected: selectedAssets.contains(asset),
                            selectionIndex: selectedAssets.firstIndex(of: asset).map { $0 + 1 },
                            onTap: {
                                toggleSelection(asset)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 90)

            Spacer().frame(height: 16)

            // Add photos button
            if !selectedAssets.isEmpty {
                Button(action: {
                    Task {
                        await addSelectedPhotos()
                    }
                }) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                    } else {
                        Text("Add \(selectedAssets.count) photo\(selectedAssets.count > 1 ? "s" : "")")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                    }
                }
                .disabled(isProcessing)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            checkCameraAvailability()
            loadRecentPhotos()
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(onImageCaptured: { image in
                Task {
                    await processCapturedImage(image)
                }
            })
        }
        .sheet(isPresented: $showingFullPicker) {
            PhotoPickerView(
                maxSelection: maxSelection - selectedAttachments.count,
                onImagesSelected: { images in
                    Task {
                        await processSelectedImages(images)
                    }
                }
            )
        }
    }

    private func checkCameraAvailability() {
        #if targetEnvironment(simulator)
        cameraAvailable = false
        #else
        cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    private func loadRecentPhotos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 20

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var photos: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(asset)
        }
        recentPhotos = photos
    }

    private func toggleSelection(_ asset: PHAsset) {
        if let index = selectedAssets.firstIndex(of: asset) {
            selectedAssets.remove(at: index)
        } else if selectedAssets.count + selectedAttachments.count < maxSelection {
            selectedAssets.append(asset)
        }
        HapticFeedback.lightImpact()
    }

    private func addSelectedPhotos() async {
        isProcessing = true

        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        for asset in selectedAssets {
            await withCheckedContinuation { continuation in
                imageManager.requestImage(
                    for: asset,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    if let image = image {
                        Task {
                            if let attachment = try? await ImageStorageService.shared.saveImage(image) {
                                await MainActor.run {
                                    selectedAttachments.append(attachment)
                                }
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }

        await MainActor.run {
            isProcessing = false
            isPresented = false
        }
    }

    private func processCapturedImage(_ image: UIImage) async {
        if let attachment = try? await ImageStorageService.shared.saveImage(image) {
            await MainActor.run {
                selectedAttachments.append(attachment)
                isPresented = false
            }
        }
    }

    private func processSelectedImages(_ images: [UIImage]) async {
        for image in images {
            if let attachment = try? await ImageStorageService.shared.saveImage(image) {
                await MainActor.run {
                    selectedAttachments.append(attachment)
                }
            }
        }
        await MainActor.run {
            isPresented = false
        }
    }
}

// MARK: - Recent Photo Thumbnail

struct RecentPhotoThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    let selectionIndex: Int?
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            .onTapGesture(perform: onTap)

            if let index = selectionIndex {
                Text("\(index)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .offset(x: -4, y: 4)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 160, height: 160),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Picker View (Full Album)

struct PhotoPickerView: UIViewControllerRepresentable {
    let maxSelection: Int
    let onImagesSelected: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = maxSelection
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            var images: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        images.append(image)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.parent.onImagesSelected(images)
            }
        }
    }
}
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Views/ImagePickerSheet.swift
git commit -m "feat: add ImagePickerSheet with camera and album support"
```

---

## Task 7: Create FullScreenImageViewer Component

**Files:**
- Create: `chatme/Views/FullScreenImageViewer.swift`

**Step 1: Create the FullScreenImageViewer file**

```swift
import SwiftUI

struct FullScreenImageViewer: View {
    let attachments: [ImageAttachment]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    @State private var currentImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    ZoomableImageView(attachment: attachment)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }

            // Page indicator
            if attachments.count > 1 {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(attachments.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.bottom, 50)
                }
            }
        }
    }
}

struct ZoomableImageView: View {
    let attachment: ImageAttachment

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1), 4)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale < 1 {
                                        withAnimation {
                                            scale = 1
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1 {
                                    scale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task {
            image = await ImageStorageService.shared.loadOriginalImage(for: attachment)
        }
    }
}
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Views/FullScreenImageViewer.swift
git commit -m "feat: add FullScreenImageViewer with zoom and swipe"
```

---

## Task 8: Create MessageImagesGrid Component

**Files:**
- Create: `chatme/Views/MessageImagesGrid.swift`

**Step 1: Create the MessageImagesGrid file**

```swift
import SwiftUI

struct MessageImagesGrid: View {
    let attachments: [ImageAttachment]
    let onTap: (Int) -> Void

    private let spacing: CGFloat = 4
    private let maxWidth: CGFloat = 200

    var body: some View {
        Group {
            switch attachments.count {
            case 1:
                singleImageLayout
            case 2:
                twoImagesLayout
            case 3:
                threeImagesLayout
            case 4:
                fourImagesLayout
            default:
                EmptyView()
            }
        }
    }

    private var singleImageLayout: some View {
        AsyncThumbnailImage(attachment: attachments[0], size: CGSize(width: maxWidth, height: maxWidth))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { onTap(0) }
    }

    private var twoImagesLayout: some View {
        HStack(spacing: spacing) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                AsyncThumbnailImage(attachment: attachment, size: CGSize(width: (maxWidth - spacing) / 2, height: (maxWidth - spacing) / 2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { onTap(index) }
            }
        }
    }

    private var threeImagesLayout: some View {
        VStack(spacing: spacing) {
            AsyncThumbnailImage(attachment: attachments[0], size: CGSize(width: maxWidth, height: (maxWidth - spacing) / 2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { onTap(0) }

            HStack(spacing: spacing) {
                ForEach(1..<3, id: \.self) { index in
                    AsyncThumbnailImage(attachment: attachments[index], size: CGSize(width: (maxWidth - spacing) / 2, height: (maxWidth - spacing) / 2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { onTap(index) }
                }
            }
        }
    }

    private var fourImagesLayout: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(0..<2, id: \.self) { index in
                    AsyncThumbnailImage(attachment: attachments[index], size: CGSize(width: (maxWidth - spacing) / 2, height: (maxWidth - spacing) / 2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { onTap(index) }
                }
            }
            HStack(spacing: spacing) {
                ForEach(2..<4, id: \.self) { index in
                    AsyncThumbnailImage(attachment: attachments[index], size: CGSize(width: (maxWidth - spacing) / 2, height: (maxWidth - spacing) / 2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { onTap(index) }
                }
            }
        }
    }
}

struct AsyncThumbnailImage: View {
    let attachment: ImageAttachment
    let size: CGSize

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size.width, height: size.height)
                    .overlay(ProgressView())
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
        }
        .task {
            isLoading = true
            image = await ImageStorageService.shared.loadThumbnail(for: attachment)
            isLoading = false
        }
    }
}
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Views/MessageImagesGrid.swift
git commit -m "feat: add MessageImagesGrid for bubble image display"
```

---

## Task 9: Update ChatMessage Model for Vision API

**Files:**
- Modify: `chatme/Models/ChatMessage.swift`

**Step 1: Update ChatMessage to support multimodal content**

Replace the entire file content:

```swift
import Foundation

// MARK: - Chat Message

struct ChatMessage: Codable {
    let role: Role
    let content: MessageContent

    enum Role: String, CaseIterable, Codable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
    }

    // MARK: - Convenience Initializers

    init(role: Role, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(role: Role, content: MessageContent) {
        self.role = role
        self.content = content
    }

    init(role: String, content: String) {
        self.role = Role(rawValue: role) ?? .user
        self.content = .text(content)
    }

    // Text-only convenience accessor
    var textContent: String {
        switch content {
        case .text(let text):
            return text
        case .multimodal(let parts):
            return parts.compactMap { part in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }.joined(separator: " ")
        }
    }

    // MARK: - Validation

    enum ValidationError: Error, LocalizedError {
        case invalidContent(String)

        var errorDescription: String? {
            switch self {
            case .invalidContent(let reason):
                return "Invalid message content: \(reason)"
            }
        }
    }

    func validate() throws {
        if textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.invalidContent("Message content cannot be empty")
        }
    }
}

// MARK: - Message Content

enum MessageContent: Codable, Equatable {
    case text(String)
    case multimodal([ContentPart])

    // Custom encoding for API compatibility
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .multimodal(let parts):
            try container.encode(parts)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as string first
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }

        // Try to decode as array of content parts
        if let parts = try? container.decode([ContentPart].self) {
            self = .multimodal(parts)
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode MessageContent")
        )
    }
}

// MARK: - Content Part

enum ContentPart: Codable, Equatable {
    case text(String)
    case imageURL(ImageURL)

    struct ImageURL: Codable, Equatable {
        let url: String

        init(base64Data: String, mimeType: String = "image/jpeg") {
            self.url = "data:\(mimeType);base64,\(base64Data)"
        }

        init(url: String) {
            self.url = url
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let imageURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let imageURL = try container.decode(ImageURL.self, forKey: .imageURL)
            self = .imageURL(imageURL)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown content type: \(type)")
            )
        }
    }
}
```

**Step 2: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add chatme/Models/ChatMessage.swift
git commit -m "feat: update ChatMessage to support Vision API multimodal content"
```

---

## Task 10: Update OpenAIService for Vision API

**Files:**
- Modify: `chatme/Services/OpenAIService.swift`

**Step 1: Update buildRequest method to support multimodal messages**

Find the `buildRequest` method and update it:

```swift
private func buildRequest(
    url: URL,
    apiKey: String,
    message: String,
    configuration: APIConfiguration,
    conversationHistory: [ChatMessage],
    imageAttachments: [ImageAttachment] = []
) async throws -> URLRequest {
    var messages: [[String: Any]] = []

    // Add system prompts
    let validSystemPrompts = configuration.systemPrompts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if !validSystemPrompts.isEmpty {
        let hasSystemMessages = conversationHistory.first?.role == .system
        if !hasSystemMessages {
            for systemPrompt in validSystemPrompts {
                messages.append(["role": "system", "content": systemPrompt])
            }
        }
    }

    // Add conversation history
    for chatMessage in conversationHistory {
        switch chatMessage.content {
        case .text(let text):
            messages.append(["role": chatMessage.role.rawValue, "content": text])
        case .multimodal(let parts):
            var contentArray: [[String: Any]] = []
            for part in parts {
                switch part {
                case .text(let text):
                    contentArray.append(["type": "text", "text": text])
                case .imageURL(let imageURL):
                    contentArray.append([
                        "type": "image_url",
                        "image_url": ["url": imageURL.url]
                    ])
                }
            }
            messages.append(["role": chatMessage.role.rawValue, "content": contentArray])
        }
    }

    // Add current user message (with images if any)
    if imageAttachments.isEmpty {
        messages.append(["role": "user", "content": message])
    } else {
        var contentArray: [[String: Any]] = []

        // Add text first
        if !message.isEmpty {
            contentArray.append(["type": "text", "text": message])
        }

        // Add images
        for attachment in imageAttachments {
            if let base64 = await ImageStorageService.shared.loadBase64(for: attachment) {
                contentArray.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ])
            }
        }

        messages.append(["role": "user", "content": contentArray])
    }

    let requestBody: [String: Any] = [
        "model": configuration.modelID,
        "messages": messages,
        "stream": true
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(Constants.contentTypeJSON, forHTTPHeaderField: "Content-Type")
    request.setValue("\(Constants.authorizationHeaderPrefix)\(apiKey)", forHTTPHeaderField: "Authorization")

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    } catch {
        throw APIError.invalidJSONResponse
    }

    return request
}
```

**Step 2: Add new sendMessage overload with image support**

Add this new method:

```swift
func sendMessageWithImages(
    _ message: String,
    images: [ImageAttachment],
    configuration: APIConfiguration,
    conversationHistory: [ChatMessage] = []
) -> AnyPublisher<String, APIError> {
    let subject = PassthroughSubject<String, APIError>()

    currentTask?.cancel()
    currentTask = Task {
        do {
            guard let apiKey = await configurationManager.getAPIKey(for: configuration) else {
                subject.send(completion: .failure(APIError.authenticationFailed("API key not found")))
                return
            }

            let urlString = configuration.baseURL.contains("/external/") || configuration.baseURL.contains("/chat/completions") ?
                configuration.baseURL : "\(configuration.baseURL)/chat/completions"

            guard let url = URL(string: urlString) else {
                subject.send(completion: .failure(APIError.invalidURL(configuration.baseURL)))
                return
            }

            let request = try await self.buildRequest(
                url: url,
                apiKey: apiKey,
                message: message,
                configuration: configuration,
                conversationHistory: conversationHistory,
                imageAttachments: images
            )

            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                subject.send(completion: .failure(APIError.invalidResponse(statusCode: 0, message: "Invalid response")))
                return
            }

            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                subject.send(completion: .failure(APIError.authenticationFailed("Invalid API key")))
                return
            case 404:
                subject.send(completion: .failure(APIError.modelNotFound(configuration.modelID)))
                return
            case 429:
                subject.send(completion: .failure(APIError.rateLimitExceeded(retryAfter: 60)))
                return
            default:
                subject.send(completion: .failure(APIError.invalidResponse(statusCode: httpResponse.statusCode, message: "Unknown error")))
                return
            }

            for try await line in bytes.lines {
                if Task.isCancelled { break }

                if let content = self.parseSSELine(line) {
                    subject.send(content)
                }
            }

            subject.send(completion: .finished)
        } catch let error as APIError {
            subject.send(completion: .failure(error))
        } catch {
            subject.send(completion: .failure(APIError.streamingError(error.localizedDescription)))
        }
    }

    return subject.eraseToAnyPublisher()
}
```

**Step 3: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add chatme/Services/OpenAIService.swift
git commit -m "feat: add Vision API support to OpenAIService"
```

---

## Task 11: Update ChatViewModel for Image Support

**Files:**
- Modify: `chatme/ViewModels/ChatViewModel.swift`

**Step 1: Add image attachment state**

Add these properties after the existing @Published properties:

```swift
@Published var pendingImageAttachments: [ImageAttachment] = []
```

**Step 2: Update MessageViewModel to include image attachments**

Update the MessageViewModel struct:

```swift
struct MessageViewModel: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    let imageAttachments: [ImageAttachment]

    init(id: UUID = UUID(), content: String, isFromUser: Bool, timestamp: Date, imageAttachments: [ImageAttachment] = []) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.imageAttachments = imageAttachments
    }

    var hasImages: Bool {
        !imageAttachments.isEmpty
    }

    static func == (lhs: MessageViewModel, rhs: MessageViewModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.isFromUser == rhs.isFromUser &&
               lhs.timestamp == rhs.timestamp &&
               lhs.imageAttachments == rhs.imageAttachments
    }
}
```

**Step 3: Update sendMessage to handle images**

Update the sendMessage method:

```swift
@MainActor
func sendMessage() {
    let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasImages = !pendingImageAttachments.isEmpty

    guard (hasText || hasImages),
          let configuration = configurationManager.activeConfiguration else {
        return
    }

    let userMessage = inputText
    let attachments = pendingImageAttachments

    inputText = ""
    pendingImageAttachments = []

    // Add user message immediately
    let userMessageVM = MessageViewModel(
        content: userMessage,
        isFromUser: true,
        timestamp: Date(),
        imageAttachments: attachments
    )
    messages.append(userMessageVM)
    saveMessage(userMessageVM)

    // Add loading assistant message
    let loadingMessageVM = MessageViewModel(content: "", isFromUser: false, timestamp: Date())
    messages.append(loadingMessageVM)

    isLoading = true
    currentError = nil

    // Build conversation history
    let conversationHistory = messages.dropLast().compactMap { messageVM -> ChatMessage? in
        guard !messageVM.content.isEmpty || messageVM.hasImages else { return nil }

        if messageVM.hasImages {
            var parts: [ContentPart] = []
            if !messageVM.content.isEmpty {
                parts.append(.text(messageVM.content))
            }
            // Note: We don't include historical images in the API call to save tokens
            // Only the current message's images are sent
            return ChatMessage(role: messageVM.isFromUser ? .user : .assistant, content: messageVM.content)
        } else {
            return ChatMessage(role: messageVM.isFromUser ? .user : .assistant, content: messageVM.content)
        }
    }

    // Choose the appropriate API method
    let publisher: AnyPublisher<String, APIError>
    if attachments.isEmpty {
        publisher = openAIService.sendMessage(userMessage, configuration: configuration, conversationHistory: conversationHistory)
    } else {
        publisher = openAIService.sendMessageWithImages(userMessage, images: attachments, configuration: configuration, conversationHistory: conversationHistory)
    }

    publisher
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoading = false

                switch completion {
                case .finished:
                    if let lastMessage = self?.messages.last, !lastMessage.isFromUser {
                        self?.saveMessage(lastMessage)
                    }
                    HapticFeedback.messageReceived()

                case .failure(let error):
                    self?.currentError = error
                    self?.messages.removeLast()
                    HapticFeedback.errorOccurred()
                }
            },
            receiveValue: { [weak self] content in
                guard let self = self, let lastIndex = self.messages.lastIndex(where: { !$0.isFromUser }) else {
                    return
                }

                let lastMessage = self.messages[lastIndex]
                let updatedContent = lastMessage.content + content

                self.messages[lastIndex] = MessageViewModel(
                    id: lastMessage.id,
                    content: updatedContent,
                    isFromUser: false,
                    timestamp: lastMessage.timestamp
                )
            }
        )
        .store(in: &cancellables)
}
```

**Step 4: Add image management methods**

```swift
// MARK: - Image Management

func addImageAttachment(_ attachment: ImageAttachment) {
    guard pendingImageAttachments.count < ImageCompressionConfig.maxImageCount else { return }
    pendingImageAttachments.append(attachment)
}

func removeImageAttachment(_ attachment: ImageAttachment) {
    pendingImageAttachments.removeAll { $0.id == attachment.id }
    // Also delete the file
    Task {
        await ImageStorageService.shared.deleteImage(attachment)
    }
}

func clearPendingImages() {
    let attachments = pendingImageAttachments
    pendingImageAttachments = []
    Task {
        await ImageStorageService.shared.deleteImages(attachments)
    }
}
```

**Step 5: Update loadMessages to include image attachments**

Update the `loadMessages(for:)` method:

```swift
private func loadMessages(for conversation: Conversation) {
    let request: NSFetchRequest<Message> = Message.fetchRequest()
    request.predicate = NSPredicate(format: "conversation == %@", conversation)
    request.sortDescriptors = [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)]

    do {
        let coreDataMessages = try managedObjectContext.fetch(request)
        messages = coreDataMessages.map { message in
            MessageViewModel(
                id: message.id ?? UUID(),
                content: message.content ?? "",
                isFromUser: message.isFromUser,
                timestamp: message.timestamp ?? Date(),
                imageAttachments: message.imageAttachmentsList
            )
        }
    } catch {
        print("Failed to load messages for conversation: \(error)")
        messages = []
    }
}
```

**Step 6: Update saveMessage to include image attachments**

```swift
private func saveMessage(_ messageViewModel: MessageViewModel) {
    let message = Message(context: managedObjectContext)
    message.id = messageViewModel.id
    message.content = messageViewModel.content
    message.isFromUser = messageViewModel.isFromUser
    message.timestamp = messageViewModel.timestamp
    message.imageAttachmentsList = messageViewModel.imageAttachments

    if let conversation = currentConversation {
        message.conversation = conversation
    }

    do {
        try managedObjectContext.save()
    } catch {
        print("Failed to save message: \(error)")
    }
}
```

**Step 7: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add chatme/ViewModels/ChatViewModel.swift
git commit -m "feat: add image support to ChatViewModel"
```

---

## Task 12: Update ChatView for Image Input

**Files:**
- Modify: `chatme/Views/ChatView.swift`

**Step 1: Add state variables for image picker**

Add after existing @State properties:

```swift
@State private var showingImagePicker = false
```

**Step 2: Update inputAreaView to include + button and image preview**

Replace the inputAreaView computed property:

```swift
// MARK: - Input Area View
private var inputAreaView: some View {
    VStack(spacing: 0) {
        // Image preview row (if any images selected)
        if !chatViewModel.pendingImageAttachments.isEmpty {
            ImagePreviewRow(
                attachments: chatViewModel.pendingImageAttachments,
                onDelete: { attachment in
                    chatViewModel.removeImageAttachment(attachment)
                }
            )
        }

        // Input row
        HStack(spacing: 12) {
            // Plus button for image picker
            Button(action: {
                showingImagePicker = true
                HapticFeedback.lightImpact()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.gray)
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }

            // Text input
            HStack(spacing: 8) {
                TextField("Type a message...", text: $chatViewModel.inputText, axis: .vertical)
                    .font(.inputFont)
                    .textFieldStyle(.plain)
                    .disabled(chatViewModel.isLoading)
                    .lineLimit(1...6)
                    .onSubmit {
                        if !chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chatViewModel.pendingImageAttachments.isEmpty {
                            sendMessage()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Send button
            Button {
                sendMessage()
            } label: {
                Image(systemName: chatViewModel.isLoading ? "stop.circle.fill" : "paperplane.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(sendButtonColor)
                    .frame(width: 40, height: 40)
                    .background(sendButtonBackgroundColor)
                    .clipShape(Circle())
                    .loadingAnimation(chatViewModel.isLoading)
            }
            .disabled(shouldDisableSendButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    .background(Color.chatBackground)
}
```

**Step 3: Update shouldDisableSendButton**

```swift
private var shouldDisableSendButton: Bool {
    let hasText = !chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasImages = !chatViewModel.pendingImageAttachments.isEmpty
    return !(hasText || hasImages) && !chatViewModel.isLoading
}
```

**Step 4: Add sheet for image picker**

Add to the end of chatContentView, after existing .sheet modifiers:

```swift
.sheet(isPresented: $showingImagePicker) {
    ImagePickerSheet(
        selectedAttachments: $chatViewModel.pendingImageAttachments,
        isPresented: $showingImagePicker,
        maxSelection: ImageCompressionConfig.maxImageCount
    )
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
}
```

**Step 5: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add chatme/Views/ChatView.swift
git commit -m "feat: add image picker UI to ChatView"
```

---

## Task 13: Update MessageBubbleView to Display Images

**Files:**
- Modify: `chatme/Views/MessageBubbleView.swift`

**Step 1: Add state for full screen image viewer**

Add after existing @State properties:

```swift
@State private var showingFullScreenImage = false
@State private var selectedImageIndex = 0
```

**Step 2: Update messageBubble to show images**

Update the messageBubble computed property to include images:

```swift
private var messageBubble: some View {
    Group {
        if message.content.isEmpty && !message.isFromUser && !message.hasImages {
            // Typing indicator
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(typingAnimation ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: typingAnimation
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onAppear {
                typingAnimation = true
            }
        } else {
            if message.isFromUser {
                // User messages
                VStack(alignment: .trailing, spacing: 8) {
                    // Images (if any)
                    if message.hasImages {
                        MessageImagesGrid(
                            attachments: message.imageAttachments,
                            onTap: { index in
                                selectedImageIndex = index
                                showingFullScreenImage = true
                            }
                        )
                    }

                    // Text (if any)
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.messageFont)
                            .foregroundColor(textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(messageBubbleColor)
                            .clipShape(messageBubbleShape)
                            .textSelection(.enabled)
                    }
                }
            } else {
                // Assistant messages
                SmartMarkdownRenderer(content: message.content)
                    .padding(.vertical, 12)
            }
        }
    }
    .fullScreenCover(isPresented: $showingFullScreenImage) {
        FullScreenImageViewer(
            attachments: message.imageAttachments,
            currentIndex: selectedImageIndex
        )
    }
}
```

**Step 3: Verify file compiles**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add chatme/Views/MessageBubbleView.swift
git commit -m "feat: add image display to MessageBubbleView"
```

---

## Task 14: Add Camera Permission to Info.plist

**Files:**
- Modify: `chatme/Info.plist` (or add key via Xcode project settings)

**Step 1: Add NSCameraUsageDescription**

The app needs camera permission. Add to Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>ChatMe needs access to your camera to take photos for conversations.</string>
```

**Step 2: Add NSPhotoLibraryUsageDescription (optional, PHPicker doesn't require it)**

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>ChatMe needs access to your photo library to share images in conversations.</string>
```

**Step 3: Commit**

```bash
git add chatme/Info.plist
git commit -m "feat: add camera and photo library permission descriptions"
```

---

## Task 15: Final Integration Test

**Step 1: Build the project**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

**Step 2: Run the app in simulator**

Run: `xcrun simctl boot "iPhone 16" 2>/dev/null; open -a Simulator`

Test the following:
1. Tap + button → Image picker sheet appears
2. Select photos → Photos appear in preview row above input
3. Tap X on preview → Photo is removed
4. Send message with photos → Photos appear in message bubble
5. Tap on photo in bubble → Full screen viewer opens
6. Pinch to zoom, swipe between photos

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete image support implementation"
```

---

## Summary

This plan implements the complete image support feature for ChatMe:

1. **Task 1-3**: Data models and storage infrastructure
2. **Task 4-8**: UI components (thumbnails, preview, picker, viewer, grid)
3. **Task 9-10**: API integration for Vision API
4. **Task 11-13**: Integration with existing ChatViewModel and views
5. **Task 14-15**: Permissions and final testing

Total: 15 tasks, each with clear steps and commit points.
