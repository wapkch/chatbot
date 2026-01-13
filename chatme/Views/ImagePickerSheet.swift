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
    @State private var selectedAssets: Set<PHAsset> = []
    @State private var showingFullPicker = false
    @State private var showingCamera = false
    @State private var hasPhotoPermission = false
    @State private var hasCameraPermission = false
    @State private var isLoadingPhotos = true

    private let photoManager = PHImageManager.default()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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

                // Bottom button
                if !selectedAssets.isEmpty {
                    addPhotosButton
                }
            }
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showingFullPicker) {
            PhotoPickerView(
                selectedImages: $selectedImages,
                isPresented: $showingFullPicker,
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

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.blue)

            Spacer()

            Text("ChatMe")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            Button("All Photos") {
                showingFullPicker = true
            }
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
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
            LazyHStack(spacing: 8) {
                // Camera button (if camera is available and we have permission)
                if UIImagePickerController.isSourceTypeAvailable(.camera) && hasCameraPermission {
                    cameraButton
                }

                // Recent photos
                ForEach(recentPhotos, id: \.localIdentifier) { asset in
                    RecentPhotoThumbnail(
                        asset: asset,
                        isSelected: selectedAssets.contains(asset),
                        selectionIndex: Array(selectedAssets).firstIndex(of: asset).map { $0 + 1 },
                        maxSelection: maxSelection,
                        selectedCount: selectedAssets.count
                    ) { asset in
                        toggleSelection(for: asset)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 120)
        .padding(.vertical, 16)
    }

    // MARK: - Camera Button

    private var cameraButton: some View {
        Button(action: {
            showingCamera = true
        }) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(width: 80, height: 80)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                        Text("Camera")
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
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
            HStack {
                Image(systemName: "plus")
                Text("Add \(selectedAssets.count) photo\(selectedAssets.count == 1 ? "" : "s")")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
        if selectedAssets.contains(asset) {
            selectedAssets.remove(asset)
        } else if selectedAssets.count < maxSelection {
            selectedAssets.insert(asset)
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
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 80, height: 80)

                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(12)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }

                // Selection overlay
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 3)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )

                    // Selection number badge
                    if let index = selectionIndex {
                        VStack {
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Text("\(index)")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                    )
                            }
                            Spacer()
                        }
                        .padding(4)
                    }
                }

                // Disabled overlay for max selection
                if !isSelected && selectedCount >= maxSelection {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
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
        requestOptions.deliveryMode = .fastFormat
        requestOptions.resizeMode = .fast
        requestOptions.isSynchronous = false

        photoManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 160, height: 160), // 2x for retina
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
                }
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