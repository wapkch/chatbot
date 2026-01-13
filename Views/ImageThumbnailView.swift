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
        do {
            thumbnailImage = try await ImageStorageService.shared.loadThumbnail(for: attachment)
        } catch {
            // Handle error gracefully - thumbnailImage remains nil
            print("Failed to load thumbnail: \(error)")
        }
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
        do {
            thumbnailImage = try await ImageStorageService.shared.loadThumbnail(for: attachment)
        } catch {
            // Handle error gracefully - thumbnailImage remains nil
            print("Failed to load thumbnail: \(error)")
        }
        isLoading = false
    }
}