import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

// MARK: - ImagePickerSheet (Main Component)

struct ImagePickerSheet: View {
    @Binding var selectedImages: [UIImage]
    @Binding var isPresented: Bool
    let maxSelection: Int

    @State private var recentPhotos: [PHAsset] = []
    @State private var selectedAssets: [PHAsset] = []  // Changed to Array for ordered selection
    @State private var showingFullPicker = false
    @State private var showingCamera = false
    @State private var hasPhotoPermission = false
    @State private var hasCameraPermission = false
    @State private var isLoadingPhotos = true

    private let photoManager = PHImageManager.default()

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            dragIndicator

            // Header
            headerView

            // Content
            if isLoadingPhotos {
                loadingView
            } else if hasPhotoPermission {
                photoGridView
            } else {
                permissionView
            }

            Spacer(minLength: 0)

            // Bottom button
            if !selectedAssets.isEmpty {
                addPhotosButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .presentationBackground(.regularMaterial)
        .sheet(isPresented: $showingFullPicker) {
            PhotoPickerView(
                selectedImages: $selectedImages,
                isPresented: $showingFullPicker,
                sheetPresented: $isPresented,
                maxSelection: maxSelection
            )
        }
        .sheet(isPresented: $showingCamera) {
            if hasCameraPermission {
                CameraView(
                    selectedImages: $selectedImages,
                    isPresented: $showingCamera
                )
            }
        }
        .onAppear {
            requestPermissionsAndLoadPhotos()
        }
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text("ChatMe")
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            Button("All Photos") {
                showingFullPicker = true
            }
            .foregroundColor(.blue)
            .font(.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Selected Preview Row

    private var selectedPreviewRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected (\(selectedAssets.count)/\(maxSelection))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(selectedAssets), id: \.localIdentifier) { asset in
                        SelectedAssetThumbnail(asset: asset) {
                            toggleSelection(for: asset)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 70)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading photos...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Photo Access Required")
                .font(.headline)

            Text("ChatMe needs access to your photos to let you share images in conversations.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Allow Photo Access") {
                Task {
                    await requestPhotoPermission()
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - Photo Grid View

    private var photoGridView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                // Camera button (always show, even without permission - will request on tap)
                cameraButton

                // Recent photos
                ForEach(recentPhotos, id: \.localIdentifier) { asset in
                    RecentPhotoThumbnail(
                        asset: asset,
                        isSelected: selectedAssets.contains(asset),
                        selectionIndex: selectedAssets.firstIndex(of: asset).map { $0 + 1 },
                        maxSelection: maxSelection,
                        selectedCount: selectedAssets.count
                    ) { asset in
                        toggleSelection(for: asset)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 120)
        .padding(.top, 8)
    }

    // MARK: - Camera Button

    // MARK: - Camera Button

    private var cameraButton: some View {
        Button(action: {
            if hasCameraPermission {
                showingCamera = true
            } else {
                Task { await requestCameraPermission() }
            }
        }) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "camera")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                )
        }
    }

    // MARK: - Add Photos Button

    private var addPhotosButton: some View {
        Button(action: {
            Task {
                await convertSelectedAssetsToImages()
            }
        }) {
            Text("Add \(selectedAssets.count) photo\(selectedAssets.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.black)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 12)
    }

    // MARK: - Private Methods

    private func requestPermissionsAndLoadPhotos() {
        Task {
            await requestPhotoPermission()
            await requestCameraPermission()
            if hasPhotoPermission {
                await loadRecentPhotos()
            }
        }
    }

    private func requestPhotoPermission() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            await MainActor.run {
                hasPhotoPermission = true
            }
            await loadRecentPhotos()
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                hasPhotoPermission = (newStatus == .authorized || newStatus == .limited)
            }
            if hasPhotoPermission {
                await loadRecentPhotos()
            }
        default:
            await MainActor.run {
                hasPhotoPermission = false
            }
        }
    }

    private func requestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            await MainActor.run {
                hasCameraPermission = true
            }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                hasCameraPermission = granted
            }
        default:
            await MainActor.run {
                hasCameraPermission = false
            }
        }
    }

    private func loadRecentPhotos() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 20
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        let assets = PHAsset.fetchAssets(with: fetchOptions)

        var photos: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(asset)
        }

        await MainActor.run {
            self.recentPhotos = photos
            self.isLoadingPhotos = false
        }
    }

    private func toggleSelection(for asset: PHAsset) {
        if let index = selectedAssets.firstIndex(of: asset) {
            selectedAssets.remove(at: index)
        } else if selectedAssets.count < maxSelection {
            selectedAssets.append(asset)
        }
    }

    private func convertSelectedAssetsToImages() async {
        var images: [UIImage] = []
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        await withTaskGroup(of: UIImage?.self) { group in
            for asset in selectedAssets {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        self.photoManager.requestImage(
                            for: asset,
                            targetSize: PHImageManagerMaximumSize,
                            contentMode: .aspectFill,
                            options: requestOptions
                        ) { image, _ in
                            continuation.resume(returning: image)
                        }
                    }
                }
            }

            for await image in group {
                if let image = image {
                    images.append(image)
                }
            }
        }

        await MainActor.run {
            self.selectedImages = images
            self.isPresented = false
        }
    }
}

// MARK: - RecentPhotoThumbnail

struct RecentPhotoThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    let selectionIndex: Int?
    let maxSelection: Int
    let selectedCount: Int
    let onTap: (PHAsset) -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    private let photoManager = PHImageManager.default()

    var body: some View {
        Button(action: {
            if !isSelected && selectedCount >= maxSelection {
                return // Don't allow selection beyond max
            }
            onTap(asset)
        }) {
            ZStack(alignment: .topTrailing) {
                // Photo thumbnail
                Group {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                    } else if isLoading {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 100, height: 100)
                            .overlay(ProgressView().scaleEffect(0.8))
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )

                // Selection badge (top-right corner)
                if isSelected, let index = selectionIndex {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Text("\(index)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        )
                        .offset(x: -6, y: 6)
                } else if !isSelected && selectedCount < maxSelection {
                    // Empty selection circle
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                        .offset(x: -6, y: 6)
                }

                // Disabled overlay for max selection
                if !isSelected && selectedCount >= maxSelection {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 100, height: 100)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        requestOptions.isSynchronous = false
        requestOptions.isNetworkAccessAllowed = true

        photoManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 160, height: 160), // 2x for retina
            contentMode: .aspectFill,
            options: requestOptions
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
                // Check if this is the final result (not a degraded version)
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - CameraView (UIKit Wrapper)

struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImages.append(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - PhotoPickerView (PHPicker Wrapper)

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Binding var isPresented: Bool
    @Binding var sheetPresented: Bool
    let maxSelection: Int

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = maxSelection
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false

            guard !results.isEmpty else { return }

            Task {
                var images: [UIImage] = []

                for result in results {
                    if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                        do {
                            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSItemProviderReading?, Error>) in
                                _ = result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                                    if let error = error {
                                        continuation.resume(throwing: error)
                                    } else {
                                        continuation.resume(returning: image)
                                    }
                                }
                            } as? UIImage
                            if let image = image {
                                images.append(image)
                            }
                        } catch {
                            print("Error loading image: \(error)")
                        }
                    }
                }

                await MainActor.run {
                    self.parent.selectedImages = images
                    self.parent.sheetPresented = false
                }
            }
        }
    }
}

// MARK: - SelectedAssetThumbnail

struct SelectedAssetThumbnail: View {
    let asset: PHAsset
    let onRemove: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    private let photoManager = PHImageManager.default()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                } else if isLoading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(ProgressView().scaleEffect(0.6))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .fastFormat
        requestOptions.resizeMode = .fast
        requestOptions.isSynchronous = false

        photoManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill,
            options: requestOptions
        ) { image, _ in
            DispatchQueue.main.async {
                self.image = image
                self.isLoading = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedImages: [UIImage] = []
        @State private var showingPicker = true

        var body: some View {
            Button("Show Picker") {
                showingPicker = true
            }
            .sheet(isPresented: $showingPicker) {
                ImagePickerSheet(
                    selectedImages: $selectedImages,
                    isPresented: $showingPicker,
                    maxSelection: 4
                )
            }
        }
    }

    return PreviewWrapper()
}