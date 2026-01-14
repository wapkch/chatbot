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
    @State private var hasError = false

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
        .asyncImageLoader(
            attachment: attachment,
            thumbnailImage: $image,
            isLoading: $isLoading,
            hasError: $hasError
        )
    }
}