import SwiftUI

// MARK: - Shared Image Loading Logic

/// A view modifier that provides shared image loading functionality with proper task management
struct AsyncImageLoader: ViewModifier {
    let attachment: ImageAttachment
    @Binding var thumbnailImage: UIImage?
    @Binding var isLoading: Bool
    @Binding var hasError: Bool

    @State private var loadingTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .task {
                loadingTask = Task {
                    await loadThumbnail()
                }
            }
            .onDisappear {
                loadingTask?.cancel()
                loadingTask = nil
            }
    }

    private func loadThumbnail() async {
        isLoading = true
        hasError = false

        do {
            let image = try await ImageStorageService.shared.loadThumbnail(for: attachment)

            // Check if task was cancelled before updating state
            if !Task.isCancelled {
                thumbnailImage = image
                isLoading = false
            }
        } catch {
            // Check if task was cancelled before updating state
            if !Task.isCancelled {
                print("Failed to load thumbnail: \(error)")
                hasError = true
                isLoading = false
            }
        }
    }
}

extension View {
    func asyncImageLoader(
        attachment: ImageAttachment,
        thumbnailImage: Binding<UIImage?>,
        isLoading: Binding<Bool>,
        hasError: Binding<Bool>
    ) -> some View {
        self.modifier(AsyncImageLoader(
            attachment: attachment,
            thumbnailImage: thumbnailImage,
            isLoading: isLoading,
            hasError: hasError
        ))
    }
}

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
    @State private var hasError = false

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
                        .accessibilityLabel("Image thumbnail")
                        .accessibilityAddTraits(.isImage)
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityLabel("Loading image")
                        )
                        .accessibilityAddTraits(.updatesFrequently)
                } else if hasError {
                    Rectangle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: size, height: size)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                    .font(.system(size: size * 0.2))
                                Text("Failed to load")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        )
                        .accessibilityLabel("Failed to load image")
                        .accessibilityAddTraits(.isImage)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                                .font(.system(size: size * 0.3))
                        )
                        .accessibilityLabel("No image available")
                        .accessibilityAddTraits(.isImage)
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
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isSelected ? "Selected image thumbnail, tap to view" : "Tap to select or view image")

            // Selection index badge
            if let index = selectionIndex {
                Text("\(index)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .offset(x: -4, y: 4)
                    .accessibilityLabel("Selection number \(index)")
                    .accessibilityAddTraits(.isStaticText)
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
                .accessibilityLabel("Delete image")
                .accessibilityHint("Double tap to remove this image")
            }
        }
        .asyncImageLoader(
            attachment: attachment,
            thumbnailImage: $thumbnailImage,
            isLoading: $isLoading,
            hasError: $hasError
        )
    }
}

// MARK: - Preview Image Thumbnail (for input area)

struct PreviewImageThumbnail: View {
    let attachment: ImageAttachment
    let onDelete: () -> Void

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                        .accessibilityLabel("Preview image")
                        .accessibilityAddTraits(.isImage)
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityLabel("Loading preview image")
                        )
                        .accessibilityAddTraits(.updatesFrequently)
                } else if hasError {
                    Rectangle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                    .font(.system(size: 16))
                                Text("Failed to load")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        )
                        .accessibilityLabel("Failed to load preview image")
                        .accessibilityAddTraits(.isImage)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                                .font(.system(size: 24))
                        )
                        .accessibilityLabel("No preview image available")
                        .accessibilityAddTraits(.isImage)
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
            .accessibilityLabel("Delete preview image")
            .accessibilityHint("Double tap to remove this preview image")
        }
        .accessibilityElement(children: .combine)
        .asyncImageLoader(
            attachment: attachment,
            thumbnailImage: $thumbnailImage,
            isLoading: $isLoading,
            hasError: $hasError
        )
    }
}