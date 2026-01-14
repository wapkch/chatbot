import SwiftUI

struct FullScreenImageViewer: View {
    let attachments: [ImageAttachment]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

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
                        .foregroundColor(.white)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task {
            do {
                let loadedImage = try await ImageStorageService.shared.loadOriginalImage(for: attachment)
                image = loadedImage
            } catch {
                print("Failed to load full screen image: \(error)")
            }
        }
    }
}